import SwiftUI

struct ConnectionView: View {
    @Bindable var store: SessionStore

    @State private var serverURL = ""
    @State private var apiKey = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case serverURL
        case apiKey
    }

    var body: some View {
        Form {
            switch store.state {
            case .disconnected, .connecting:
                connectionForm
            case let .connected(serverURL, collections):
                connectedContent(serverURL: serverURL, collections: collections)
            }
        }
        .navigationTitle("Outline")
        .refreshable {
            await store.refreshCollections()
        }
    }

    @ViewBuilder
    private var connectionForm: some View {
        Section("Connection") {
            LabeledContent("Server URL") {
                TextField("https://outline.example.com", text: $serverURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .serverURL)
                    .onSubmit { focusedField = .apiKey }
                    .accessibilityLabel("Server URL")
            }

            LabeledContent("API key") {
                SecureField("Paste API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focusedField, equals: .apiKey)
                    .onSubmit(connect)
                    .accessibilityLabel("API key")
            }

            Text("Connection checks collection, search, and available document access. Protected images also require attachments.redirect.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(store.isConnecting)

        errorContent

        Section {
            Button(action: connect) {
                if store.isConnecting {
                    HStack {
                        ProgressView()
                        Text("Connecting…")
                    }
                } else {
                    Text("Connect")
                }
            }
            .disabled(store.isConnecting)
            .accessibilityLabel(store.isConnecting ? "Connecting" : "Connect")
        }
    }

    @ViewBuilder
    private func connectedContent(serverURL: URL, collections: [OutlineCollection]) -> some View {
        Section("Connected server") {
            LabeledContent("Server URL") {
                Text(serverURL.absoluteString)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }

        Section {
            NavigationLink {
                DocumentSearchView(store: store)
            } label: {
                Label("Search documents", systemImage: "magnifyingglass")
            }
        }

        Section("Collections") {
            if collections.isEmpty {
                Text("No collections found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(collections, id: \.id) { collection in
                    NavigationLink {
                        DocumentListView(store: store, collection: collection)
                    } label: {
                        Text(collection.name)
                    }
                }
            }
        }

        errorContent

        Section {
            Button("Disconnect", action: store.disconnect)
        }
    }

    @ViewBuilder
    private var errorContent: some View {
        if let errorMessage = store.errorMessage {
            Section {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Error. \(errorMessage)")
            }
        }
    }

    private func connect() {
        guard !store.isConnecting else { return }

        Task {
            await store.connect(serverURL: serverURL, token: apiKey)
            if case .connected = store.state {
                apiKey = ""
                focusedField = nil
            }
        }
    }
}

private struct DocumentSearchView: View {
    let store: SessionStore

    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var request = 0
    @State private var state = SearchState.idle

    var body: some View {
        Group {
            switch state {
            case .idle:
                ContentUnavailableView(
                    "Search documents",
                    systemImage: "magnifyingglass",
                    description: Text("Enter a title or phrase.")
                )
            case .loading:
                ProgressView("Searching…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(results):
                if results.isEmpty {
                    ContentUnavailableView.search(text: submittedQuery)
                } else {
                    List(results) { result in
                        NavigationLink {
                            DocumentReaderView(
                                store: store,
                                documentID: result.id,
                                documentPath: result.url
                            )
                        } label: {
                            Text(result.title)
                        }
                    }
                }
            case let .failed(message):
                ContentUnavailableView {
                    Label("Unable to search documents", systemImage: "exclamationmark.circle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { request += 1 }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search documents")
        .onSubmit(of: .search, submit)
        .task(id: request) {
            guard !submittedQuery.isEmpty else { return }
            state = .loading
            do {
                state = .loaded(try await store.searchDocuments(query: submittedQuery))
            } catch is CancellationError {
                return
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func submit() {
        request += 1
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            submittedQuery = ""
            state = .idle
            return
        }
        submittedQuery = trimmedQuery
    }

    private enum SearchState {
        case idle
        case loading
        case loaded([OutlineSearchResult])
        case failed(String)
    }
}
