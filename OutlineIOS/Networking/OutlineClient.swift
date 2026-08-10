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
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("3", forHTTPHeaderField: "X-API-Version")
        request.httpBody = Data("{}".utf8)

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
            return try JSONDecoder().decode(CollectionsResponse.self, from: data).data
        } catch {
            throw OutlineClientError.decodingFailed
        }
    }

    private var endpointURL: URL {
        baseURL
            .appendingPathComponent("api", isDirectory: true)
            .appendingPathComponent("collections.list")
    }

    private static func isValidBaseURL(_ url: URL) -> Bool {
        url.scheme?.caseInsensitiveCompare("https") == .orderedSame
            && !(url.host?.isEmpty ?? true)
            && url.query == nil
            && url.fragment == nil
    }

    private struct CollectionsResponse: Decodable {
        let data: [OutlineCollection]
    }
}
