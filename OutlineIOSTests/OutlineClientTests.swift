import OutlineCore
import Foundation
import Testing
@testable import Outline

@Suite(.serialized)
struct OutlineClientTests {
    @Test
    func buildsSelfHostedPathAndRequiredRequest() async throws {
        let capture = RequestCapture()
        URLProtocolStub.handler = { request in
            capture.store(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return StubResult(response: response, data: Data("{\"data\":[]}".utf8))
        }
        defer { URLProtocolStub.handler = nil }

        let session = makeStubSession()
        let client = try OutlineClient(
            baseURL: URL(string: "https://outline.example/team/")!,
            token: "secret-token",
            session: session
        )

        _ = try await client.listCollections()

        let request = try #require(capture.value)
        #expect(request.url?.absoluteString == "https://outline.example/team/api/collections.list")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-API-Version") == "3")
        let body = try #require(capture.body)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["limit"] as? Int == 100)
        #expect(json["offset"] as? Int == 0)
    }

    @Test
    func decodesCollections() async throws {
        URLProtocolStub.handler = { request in
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let body = "{\"data\":[{\"id\":\"one\",\"name\":\"First\"},{\"id\":\"two\",\"name\":\"Second\"}]}"
            return StubResult(response: response, data: Data(body.utf8))
        }
        defer { URLProtocolStub.handler = nil }

        let client = try OutlineClient(
            baseURL: URL(string: "https://outline.example")!,
            token: "token",
            session: makeStubSession()
        )

        let collections = try await client.listCollections()

        #expect(collections == [
            OutlineCollection(id: "one", name: "First"),
            OutlineCollection(id: "two", name: "Second")
        ])
    }

    @Test
    func loadsAllCollectionPages() async throws {
        let capture = RequestCapture()
        URLProtocolStub.handler = { request in
            capture.store(request)
            let offset = capture.count == 1 ? 0 : 100
            let count = offset == 0 ? 100 : 1
            let items = (offset..<(offset + count)).map {
                ["id": "collection-\($0)", "name": "Collection \($0)"]
            }
            let body = try JSONSerialization.data(withJSONObject: [
                "pagination": ["total": 101],
                "data": items,
            ])
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return StubResult(response: response, data: body)
        }
        defer { URLProtocolStub.handler = nil }

        let client = try OutlineClient(
            baseURL: URL(string: "https://outline.example")!,
            token: "token",
            session: makeStubSession()
        )

        let collections = try await client.listCollections()

        #expect(collections.count == 101)
        #expect(collections.last?.id == "collection-100")
        #expect(capture.count == 2)
        let body = try #require(capture.body)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["limit"] as? Int == 100)
        #expect(json["offset"] as? Int == 100)
    }

    @Test
    func diagnosesMissingCollectionDocumentsPermissionBeforeConnecting() async throws {
        let capture = RequestCapture()
        URLProtocolStub.handler = { request in
            capture.store(request)
            let path = try #require(request.url?.lastPathComponent)
            let statusCode = path == "collections.documents" ? 403 : 200
            let body = switch path {
            case "collections.list": #"{"data":[{"id":"collection-id","name":"Collection"}]}"#
            case "documents.search": #"{"data":[]}"#
            default: #"{"data":{}}"#
            }
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            ))
            return StubResult(response: response, data: Data(body.utf8))
        }
        defer { URLProtocolStub.handler = nil }

        let client = try OutlineClient(
            baseURL: URL(string: "https://outline.example")!,
            token: "token",
            session: makeStubSession()
        )

        do {
            _ = try await client.validateReaderAccess()
            Issue.record("Expected permission diagnosis to fail")
        } catch let error as OutlineClientError {
            #expect(error == .missingPermission("collections.documents"))
        } catch {
            Issue.record(error)
        }
        #expect(capture.count == 3)
    }

    @Test(arguments: [
        ("documents.search", 2),
        ("documents.info", 4),
    ])
    func diagnosesMissingSearchAndDocumentInfoPermissionsBeforeConnecting(
        deniedEndpoint: String,
        expectedRequestCount: Int
    ) async throws {
        let capture = RequestCapture()
        URLProtocolStub.handler = { request in
            capture.store(request)
            let path = try #require(request.url?.lastPathComponent)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: path == deniedEndpoint ? 403 : 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let body = switch path {
            case "collections.list":
                #"{"data":[{"id":"collection-id","name":"Collection"}]}"#
            case "documents.search":
                #"{"data":[]}"#
            case "collections.documents":
                #"{"data":[{"id":"document-id","title":"Document","url":"/doc/document-id","children":[]}]}"#
            default:
                #"{"data":{"document":{"id":"document-id","title":"Document","url":"/doc/document-id","data":{"type":"doc"}}}}"#
            }
            return StubResult(response: response, data: Data(body.utf8))
        }
        defer { URLProtocolStub.handler = nil }

        let client = try OutlineClient(
            baseURL: URL(string: "https://outline.example")!,
            token: "token",
            session: makeStubSession()
        )

        do {
            _ = try await client.validateReaderAccess()
            Issue.record("Expected permission diagnosis to fail")
        } catch let error as OutlineClientError {
            #expect(error == .missingPermission(deniedEndpoint))
        } catch {
            Issue.record(error)
        }
        #expect(capture.count == expectedRequestCount)
    }

    @Test(arguments: [
        ("collections.documents", 3),
        ("documents.info", 4),
        ("attachments.redirect", 5),
    ])
    func diagnosesEveryReaderPermissionInAnEmptyWorkspace(
        deniedEndpoint: String,
        expectedRequestCount: Int
    ) async throws {
        let capture = RequestCapture()
        URLProtocolStub.handler = { request in
            capture.store(request)
            let path = try #require(request.url?.lastPathComponent)
            let statusCode: Int
            if path == deniedEndpoint {
                statusCode = 403
            } else if ["collections.list", "documents.search"].contains(path) {
                statusCode = 200
            } else {
                statusCode = 404
            }
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            ))
            return StubResult(response: response, data: Data(#"{"data":[]}"#.utf8))
        }
        defer { URLProtocolStub.handler = nil }

        let client = try OutlineClient(
            baseURL: URL(string: "https://outline.example")!,
            token: "token",
            session: makeStubSession()
        )

        do {
            _ = try await client.validateReaderAccess()
            Issue.record("Expected permission diagnosis to fail")
        } catch let error as OutlineClientError {
            #expect(error == .missingPermission(deniedEndpoint))
        } catch {
            Issue.record(error)
        }
        #expect(capture.count == expectedRequestCount)
    }

    @Test
    func buildsDocumentsPathAndRequest() async throws {
        let capture = RequestCapture()
        URLProtocolStub.handler = { request in
            capture.store(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return StubResult(response: response, data: Data("{\"data\":[]}".utf8))
        }
        defer { URLProtocolStub.handler = nil }

        let client = try OutlineClient(
            baseURL: URL(string: "https://outline.example/team/")!,
            token: "secret-token",
            session: makeStubSession()
        )

        _ = try await client.listDocuments(collectionID: "collection-id")

        let request = try #require(capture.value)
        #expect(request.url?.absoluteString == "https://outline.example/team/api/collections.documents")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-API-Version") == "3")
        #expect(capture.body == Data("{\"id\":\"collection-id\"}".utf8))
    }

    @Test
    func decodesNestedDocuments() async throws {
        URLProtocolStub.handler = { request in
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let body = """
            {"data":[{"id":"root","title":"Root","url":"/doc/root","children":[{"id":"child","title":"Child","url":"/doc/child","children":[{"id":"leaf","title":"Leaf","url":"/doc/leaf","children":[]}]}]}]}
            """
            return StubResult(response: response, data: Data(body.utf8))
        }
        defer { URLProtocolStub.handler = nil }

        let client = try OutlineClient(
            baseURL: URL(string: "https://outline.example")!,
            token: "token",
            session: makeStubSession()
        )

        let documents = try await client.listDocuments(collectionID: "collection-id")

        let leaf = OutlineDocumentNode(id: "leaf", title: "Leaf", url: "/doc/leaf", children: [])
        let child = OutlineDocumentNode(id: "child", title: "Child", url: "/doc/child", children: [leaf])
        let root = OutlineDocumentNode(id: "root", title: "Root", url: "/doc/root", children: [child])
        #expect(documents == [root])
        #expect(documents[0].outlineChildren == [child])
        #expect(documents[0].children[0].outlineChildren == [leaf])
        #expect(documents[0].children[0].children[0].outlineChildren == nil)
    }

    @Test
    func buildsDocumentsInfoRequestAndDecodesRichDocument() async throws {
        let capture = RequestCapture()
        URLProtocolStub.handler = { request in
            capture.store(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let body = """
            {
              "data": {
                "document": {
                  "id": "document-id",
                  "title": "Read me",
                  "url": "/doc/document-id",
                  "data": {
                    "type": "doc",
                    "content": [
                      {
                        "type": "paragraph",
                        "content": [
                          {
                            "type": "text",
                            "text": "Welcome",
                            "marks": [{"type": "strong"}]
                          }
                        ]
                      },
                      {
                        "type": "heading",
                        "attrs": {"level": 2},
                        "content": [{"type": "text", "text": "Details"}]
                      },
                      {
                        "type": "image",
                        "attrs": {
                          "src": "https://example.com/image.png",
                          "alt": "A sample image",
                          "layoutClass": "center"
                        }
                      }
                    ]
                  }
                }
              }
            }
            """
            return StubResult(response: response, data: Data(body.utf8))
        }
        defer { URLProtocolStub.handler = nil }

        let client = try OutlineClient(
            baseURL: URL(string: "https://outline.example/team/")!,
            token: "secret-token",
            session: makeStubSession()
        )

        let document = try await client.document(id: "document-id")

        let request = try #require(capture.value)
        #expect(request.url?.absoluteString == "https://outline.example/team/api/documents.info")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-API-Version") == "3")
        #expect(capture.body == Data(#"{"id":"document-id"}"#.utf8))
        #expect(document.id == "document-id")
        #expect(document.title == "Read me")
        #expect(document.url == "/doc/document-id")
        #expect(document.data.type == "doc")
        #expect(document.data.attrs.isEmpty)
        #expect(document.data.content.count == 3)

        let paragraph = document.data.content[0]
        #expect(paragraph.attrs.isEmpty)
        #expect(paragraph.content[0].text == "Welcome")
        #expect(paragraph.content[0].marks == [ProseMirrorMark(type: "strong")])

        let heading = document.data.content[1]
        #expect(heading.intAttribute("level") == 2)

        let image = document.data.content[2]
        #expect(image.stringAttribute("src") == "https://example.com/image.png")
        #expect(image.stringAttribute("alt") == "A sample image")
        #expect(image.stringAttribute("layoutClass") == "center")
    }

    @Test
    func searchesDocumentsAndDecodesNestedResults() async throws {
        let capture = RequestCapture()
        URLProtocolStub.handler = { request in
            capture.store(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let body = """
            {
              "pagination": {"limit": 25, "offset": 0, "total": 1},
              "data": [{
                "context": "Matching text",
                "document": {
                  "id": "document-id",
                  "title": "Product roadmap",
                  "url": "/doc/product-roadmap-id"
                }
              }]
            }
            """
            return StubResult(response: response, data: Data(body.utf8))
        }
        defer { URLProtocolStub.handler = nil }

        let client = try OutlineClient(
            baseURL: URL(string: "https://outline.example/team/")!,
            token: "secret-token",
            session: makeStubSession()
        )

        let results = try await client.searchDocuments(query: "  roadmap  ")

        let request = try #require(capture.value)
        #expect(request.url?.absoluteString == "https://outline.example/team/api/documents.search")
        let bodyData = try #require(capture.body)
        let bodyJSON = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(bodyJSON["limit"] as? Int == 100)
        #expect(bodyJSON["offset"] as? Int == 0)
        #expect(bodyJSON["query"] as? String == "roadmap")
        #expect(results.count == 1)
        #expect(results[0].id == "document-id")
        #expect(results[0].title == "Product roadmap")
        #expect(results[0].url == "/doc/product-roadmap-id")
    }

    @Test
    func loadsAllSearchPages() async throws {
        let capture = RequestCapture()
        URLProtocolStub.handler = { request in
            capture.store(request)
            let offset = capture.count == 1 ? 0 : 100
            let count = offset == 0 ? 100 : 1
            let items = (offset..<(offset + count)).map {
                [
                    "document": [
                        "id": "document-\($0)",
                        "title": "Document \($0)",
                        "url": "/doc/document-\($0)",
                    ]
                ]
            }
            let body = try JSONSerialization.data(withJSONObject: [
                "pagination": ["total": 101],
                "data": items,
            ])
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return StubResult(response: response, data: body)
        }
        defer { URLProtocolStub.handler = nil }

        let client = try OutlineClient(
            baseURL: URL(string: "https://outline.example")!,
            token: "token",
            session: makeStubSession()
        )

        let results = try await client.searchDocuments(query: "document")

        #expect(results.count == 101)
        #expect(results.last?.id == "document-100")
        #expect(capture.count == 2)
        let body = try #require(capture.body)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["limit"] as? Int == 100)
        #expect(json["offset"] as? Int == 100)
        #expect(json["query"] as? String == "document")
    }

    @Test
    func doesNotSearchBlankQuery() async throws {
        let capture = RequestCapture()
        URLProtocolStub.handler = { request in
            capture.store(request)
            throw URLError(.badURL)
        }
        defer { URLProtocolStub.handler = nil }

        let client = try OutlineClient(
            baseURL: URL(string: "https://outline.example")!,
            token: "token",
            session: makeStubSession()
        )

        let results = try await client.searchDocuments(query: " \n ")

        #expect(results.isEmpty)
        #expect(capture.value == nil)
    }

    @Test
    func routesOnlySameOriginDocumentLinks() throws {
        let serverURL = try #require(URL(string: "https://outline.example/team/"))
        let url = try #require(URL(string: "https://outline.example/doc/product-roadmap-id#Next%20Steps"))
        let target = try #require(documentLinkTarget(from: url, serverURL: serverURL))

        #expect(target.documentID == "product-roadmap-id")
        #expect(target.documentPath == "/doc/product-roadmap-id")
        #expect(target.anchor == "Next Steps")
        let externalURL = try #require(URL(string: "https://other.example/doc/document-id"))
        #expect(documentLinkTarget(from: externalURL, serverURL: serverURL) == nil)

        let collectionURL = try #require(URL(string: "https://outline.example/collection/collection-id"))
        #expect(documentLinkTarget(from: collectionURL, serverURL: serverURL) == nil)
    }

    @Test
    func preservesURLSessionCancellation() async throws {
        URLProtocolStub.handler = { _ in
            throw URLError(.cancelled)
        }
        defer { URLProtocolStub.handler = nil }

        let client = try OutlineClient(
            baseURL: URL(string: "https://outline.example")!,
            token: "token",
            session: makeStubSession()
        )

        do {
            _ = try await client.listCollections()
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected: callers keep their current content instead of showing an error.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func mapsHTTPFailure() async throws {
        URLProtocolStub.handler = { request in
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            ))
            return StubResult(response: response, data: Data("{\"error\":\"Unauthorized\"}".utf8))
        }
        defer { URLProtocolStub.handler = nil }

        let client = try OutlineClient(
            baseURL: URL(string: "https://outline.example")!,
            token: "token",
            session: makeStubSession()
        )

        do {
            _ = try await client.listCollections()
            Issue.record("Expected the client to throw for an HTTP failure")
        } catch let error as OutlineClientError {
            #expect(error == .httpFailure(statusCode: 401))
            #expect(error.localizedDescription == "The API key is invalid or expired (HTTP 401).")
            #expect(
                OutlineClientError.httpFailure(statusCode: 403).localizedDescription
                    == "The API key does not have permission for this action (HTTP 403)."
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func identifiesMissingEndpointPermission() async throws {
        URLProtocolStub.handler = { request in
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 403,
                httpVersion: nil,
                headerFields: nil
            ))
            return StubResult(response: response, data: Data())
        }
        defer { URLProtocolStub.handler = nil }

        let client = try OutlineClient(
            baseURL: URL(string: "https://outline.example")!,
            token: "token",
            session: makeStubSession()
        )

        do {
            _ = try await client.listCollections()
            Issue.record("Expected a permission failure")
        } catch let error as OutlineClientError {
            #expect(error == .missingPermission("collections.list"))
            #expect(
                error.localizedDescription
                    == "This API key needs the collections.list permission. Create a new API key with full access or this permission, then reconnect (HTTP 403)."
            )
        }
    }

    @Test
    func loadsRelativeAssetWithSameOriginAuthorization() async throws {
        let capture = RequestCapture()
        URLProtocolStub.handler = { request in
            capture.store(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return StubResult(response: response, data: Data("asset".utf8))
        }
        defer { URLProtocolStub.handler = nil }

        let client = try OutlineClient(
            baseURL: URL(string: "https://outline.example/team/")!,
            token: "secret-token",
            session: makeStubSession()
        )

        let data = try await client.assetData(for: "images/sample.png")

        let request = try #require(capture.value)
        #expect(data == Data("asset".utf8))
        #expect(request.url?.absoluteString == "https://outline.example/team/images/sample.png")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
    }

    @Test
    func doesNotAuthorizeExternalHTTPSAsset() async throws {
        let capture = RequestCapture()
        URLProtocolStub.handler = { request in
            capture.store(request)
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return StubResult(response: response, data: Data("external".utf8))
        }
        defer { URLProtocolStub.handler = nil }

        let client = try OutlineClient(
            baseURL: URL(string: "https://outline.example/team/")!,
            token: "secret-token",
            session: makeStubSession()
        )

        let data = try await client.assetData(for: "https://cdn.example/image.png")

        let request = try #require(capture.value)
        #expect(data == Data("external".utf8))
        #expect(request.url?.absoluteString == "https://cdn.example/image.png")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test
    func rejectsHTTPAndUnsafeAssetURLs() async throws {
        let client = try OutlineClient(
            baseURL: URL(string: "https://outline.example")!,
            token: "token",
            session: makeStubSession()
        )

        for source in ["http://outline.example/image.png", "file:///tmp/image.png"] {
            do {
                _ = try await client.assetData(for: source)
                Issue.record("Expected \(source) to be rejected")
            } catch let error as OutlineClientError {
                #expect(error == .invalidAssetURL)
            } catch {
                Issue.record("Unexpected error for \(source): \(error)")
            }
        }
    }

    @Test
    func mapsAssetHTTPFailure() async throws {
        URLProtocolStub.handler = { request in
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            ))
            return StubResult(response: response, data: Data())
        }
        defer { URLProtocolStub.handler = nil }

        let client = try OutlineClient(
            baseURL: URL(string: "https://outline.example")!,
            token: "token",
            session: makeStubSession()
        )

        do {
            _ = try await client.assetData(for: "/image.png")
            Issue.record("Expected the client to throw for an asset HTTP failure")
        } catch let error as OutlineClientError {
            #expect(error == .httpFailure(statusCode: 404))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func explainsMissingAttachmentRedirectScope() async throws {
        URLProtocolStub.handler = { request in
            let response = try #require(HTTPURLResponse(
                url: request.url!,
                statusCode: 403,
                httpVersion: nil,
                headerFields: nil
            ))
            return StubResult(response: response, data: Data())
        }
        defer { URLProtocolStub.handler = nil }

        let client = try OutlineClient(
            baseURL: URL(string: "https://outline.example")!,
            token: "token",
            session: makeStubSession()
        )

        do {
            _ = try await client.assetData(for: "/api/attachments.redirect?id=attachment-id")
            Issue.record("Expected attachment permission failure")
        } catch {
            #expect(
                error.localizedDescription
                    == "This API key needs the attachments.redirect permission. Create a new API key with full access or this permission, then reconnect (HTTP 403)."
            )
        }
    }

    @Test
    func rejectsNonHTTPSBaseURL() {
        #expect(throws: OutlineClientError.invalidBaseURL) {
            try OutlineClient(baseURL: URL(string: "http://outline.example")!, token: "token")
        }
    }
}

private func makeStubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    return URLSession(configuration: configuration)
}

private final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?
    private var requestBody: Data?
    private var requests = 0

    func store(_ request: URLRequest) {
        let body = request.httpBody ?? request.httpBodyStream.flatMap(Self.read)
        lock.lock()
        self.request = request
        requestBody = body
        requests += 1
        lock.unlock()
    }

    var value: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }

    var body: Data? {
        lock.lock()
        defer { lock.unlock() }
        return requestBody
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 256)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private struct StubResult {
    let response: URLResponse
    let data: Data
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> StubResult

    nonisolated(unsafe) static var handler: Handler?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let result = try handler(request)
            client?.urlProtocol(self, didReceive: result.response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
