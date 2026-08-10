import Foundation
import Observation

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
            let collections = try await client.listCollections()
            self.client = client
            state = .connected(serverURL: credentials.serverURL, collections: collections)
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
            collections = try await client.listCollections()
        } catch {
            state = .disconnected
            errorMessage = "\(error.localizedDescription) Check the server URL, API key, and network, then try again."
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

    func documents(in collectionID: String) async throws -> [OutlineDocumentNode] {
        guard let client else {
            throw OutlineClientError.requestFailed
        }

        return try await client.listDocuments(collectionID: collectionID)
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
