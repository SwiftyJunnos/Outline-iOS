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
        #expect(capture.body == Data("{}".utf8))
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
        } catch {
            Issue.record("Unexpected error: \(error)")
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

    func store(_ request: URLRequest) {
        let body = request.httpBody ?? request.httpBodyStream.flatMap(Self.read)
        lock.lock()
        self.request = request
        requestBody = body
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
