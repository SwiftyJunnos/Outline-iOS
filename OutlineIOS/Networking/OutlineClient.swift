import Foundation

enum OutlineClientError: Error, Equatable, LocalizedError, Sendable {
    case invalidBaseURL
    case invalidResponse
    case httpFailure(statusCode: Int)
    case decodingFailed
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Enter a valid HTTPS server URL."
        case .invalidResponse:
            "The server returned an invalid response."
        case .httpFailure:
            "The server rejected the request."
        case .decodingFailed:
            "The server returned an unexpected response."
        case .requestFailed:
            "Could not connect to the server."
        }
    }
}

struct OutlineClient: Sendable {
    private let baseURL: URL
    private let token: String
    private let session: URLSession

    init(baseURL: URL, token: String, session: URLSession = .shared) throws {
        guard Self.isValidBaseURL(baseURL) else {
            throw OutlineClientError.invalidBaseURL
        }

        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    func listCollections() async throws -> [OutlineCollection] {
        let response: CollectionsResponse = try await post(
            "collections.list",
            body: EmptyRequest()
        )
        return response.data
    }

    func listDocuments(collectionID: String) async throws -> [OutlineDocumentNode] {
        let response: DocumentsResponse = try await post(
            "collections.documents",
            body: CollectionDocumentsRequest(id: collectionID)
        )
        return response.data
    }

    func document(id: String) async throws -> OutlineDocument {
        let response: DocumentInfoResponse = try await post(
            "documents.info",
            body: DocumentInfoRequest(id: id),
            apiVersion: 2
        )
        return response.data.document
    }

    private func post<Response: Decodable, Body: Encodable>(
        _ path: String,
        body: Body,
        apiVersion: Int = 3
    ) async throws -> Response {
        var request = URLRequest(url: endpointURL(for: path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(String(apiVersion), forHTTPHeaderField: "X-API-Version")

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw OutlineClientError.requestFailed
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw OutlineClientError.requestFailed
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OutlineClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OutlineClientError.httpFailure(statusCode: httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw OutlineClientError.decodingFailed
        }
    }

    private func endpointURL(for path: String) -> URL {
        baseURL
            .appendingPathComponent("api", isDirectory: true)
            .appendingPathComponent(path)
    }

    private static func isValidBaseURL(_ url: URL) -> Bool {
        url.scheme?.caseInsensitiveCompare("https") == .orderedSame
            && !(url.host?.isEmpty ?? true)
            && url.query == nil
            && url.fragment == nil
    }

    private struct EmptyRequest: Encodable {}

    private struct CollectionDocumentsRequest: Encodable {
        let id: String
    }

    private struct DocumentInfoRequest: Encodable {
        let id: String
    }

    private struct DocumentInfoResponse: Decodable {
        let data: DocumentInfoData
    }

    private struct DocumentInfoData: Decodable {
        let document: OutlineDocument
    }

    private struct CollectionsResponse: Decodable {
        let data: [OutlineCollection]
    }

    private struct DocumentsResponse: Decodable {
        let data: [OutlineDocumentNode]
    }
}
