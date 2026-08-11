import OutlineCore
import Foundation
import Observation

enum SessionErrorRecovery: Equatable, Sendable {
    case reconnect
    case retry

    init(error: Error) {
        guard let error = error as? OutlineClientError else {
            self = .retry
            return
        }

        switch error {
        case .missingPermission:
            self = .reconnect
        case let .httpFailure(statusCode) where statusCode == 401 || statusCode == 403:
            self = .reconnect
        default:
            self = .retry
        }
    }
}

struct SessionErrorNotice: Equatable, Identifiable, Sendable {
    let message: String
    let recovery: SessionErrorRecovery

    init(error: Error) {
        message = error.localizedDescription
        recovery = SessionErrorRecovery(error: error)
    }

    var id: String {
        message
    }
}


@MainActor
@Observable
final class SessionStore {
    enum State {
        case disconnected
        case connecting
        case connected(serverURL: URL, collections: [OutlineCollection])
    }

    private(set) var state: State = .disconnected
    private(set) var errorMessage: String?

    private let keychainStore: KeychainStore
    private var client: OutlineClient?

    init(keychainStore: KeychainStore = KeychainStore()) {
        self.keychainStore = keychainStore
    }

    var isConnecting: Bool {
        if case .connecting = state {
            true
        } else {
            false
        }
    }

    var isConnected: Bool {
        if case .connected = state {
            true
        } else {
            false
        }
    }

    func restore() async {
        guard case .disconnected = state else { return }
        client = nil

        let credentials: Credentials
        do {
            guard let savedCredentials = try keychainStore.load() else { return }
            credentials = savedCredentials
        } catch {
            errorMessage = "Unable to read saved credentials. Enter the server URL and API key to reconnect."
            return
        }

        errorMessage = nil
        state = .connecting

        do {
            let client = try OutlineClient(baseURL: credentials.serverURL, token: credentials.token)
            let collections = try await client.validateReaderAccess()
            self.client = client
            state = .connected(serverURL: credentials.serverURL, collections: collections)
        } catch is CancellationError {
            state = .disconnected
            return
        } catch let error as OutlineClientError {
            state = .disconnected
            errorMessage = error.localizedDescription
        } catch {
            state = .disconnected
            errorMessage = "Unable to verify the saved connection. Check your network, or enter the server URL and API key to reconnect."
        }
    }

    func connect(serverURL: String, token: String) async {
        guard case .disconnected = state else { return }
        client = nil
        let trimmedServerURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedServerURL.isEmpty, let url = URL(string: trimmedServerURL) else {
            errorMessage = "Enter a valid HTTPS server URL."
            return
        }
        guard !trimmedToken.isEmpty else {
            errorMessage = "Enter an API key."
            return
        }

        errorMessage = nil
        state = .connecting

        let client: OutlineClient
        let collections: [OutlineCollection]
        do {
            client = try OutlineClient(baseURL: url, token: trimmedToken)
            collections = try await client.validateReaderAccess()
        } catch is CancellationError {
            state = .disconnected
            return
        } catch let error as OutlineClientError {
            state = .disconnected
            errorMessage = error.localizedDescription
            return
        } catch {
            state = .disconnected
            errorMessage = "Could not connect to the server. Check the server URL and network, then try again."
            return
        }

        do {
            try keychainStore.save(Credentials(serverURL: url, token: trimmedToken))
            self.client = client
            state = .connected(serverURL: url, collections: collections)
        } catch {
            state = .disconnected
            errorMessage = "Unable to save the connection securely. Check Keychain access and try again."
        }
    }

    func refreshCollections() async -> SessionErrorNotice? {
        guard
            case let .connected(serverURL, _) = state,
            let client
        else {
            return nil
        }

        do {
            state = .connected(serverURL: serverURL, collections: try await client.listCollections())
            errorMessage = nil
            return nil
        } catch is CancellationError {
            return nil
        } catch {
            return SessionErrorNotice(error: error)
        }
    }

    func documents(in collectionID: String) async throws -> [OutlineDocumentNode] {
        guard let client else {
            throw OutlineClientError.requestFailed
        }

        return try await client.listDocuments(collectionID: collectionID)
    }

    func searchDocuments(query: String) async throws -> [OutlineSearchResult] {
        guard let client else {
            throw OutlineClientError.requestFailed
        }

        return try await client.searchDocuments(query: query)
    }

    func document(id: String) async throws -> OutlineRichDocument {
        guard let client else {
            throw OutlineClientError.requestFailed
        }

        return try await client.document(id: id)
    }

    func comments(in documentID: String) async throws -> [OutlineComment] {
        guard let client else {
            throw OutlineClientError.requestFailed
        }

        return try await client.comments(in: documentID)
    }

    func createComment(in documentID: String, text: String) async throws -> OutlineComment {
        guard let client else {
            throw OutlineClientError.requestFailed
        }

        return try await client.createComment(in: documentID, text: text)
    }

    func assetData(for source: String) async throws -> Data {
        guard let client else {
            throw OutlineClientError.requestFailed
        }

        return try await client.assetData(for: source)
    }

    var connectedServerURL: URL? {
        guard case let .connected(serverURL, _) = state else { return nil }
        return serverURL
    }

    func webURL(for documentPath: String) -> URL? {
        guard case let .connected(serverURL, _) = state else { return nil }
        return URL(string: documentPath, relativeTo: serverURL)?.absoluteURL
    }

    func disconnect() {
        client = nil
        state = .disconnected

        do {
            try keychainStore.delete()
            errorMessage = nil
        } catch {
            errorMessage = "Connection closed, but saved credentials could not be removed. Check Keychain access, then reconnect and disconnect again."
        }
    }
}
