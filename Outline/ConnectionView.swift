import SwiftUI

struct ConnectionView: View {
    @Bindable var store: SessionStore

    @State private var serverURL = ""
    @State private var apiKey = ""
    @FocusState private var focusedField: Field?
    @State private var refreshError: SessionErrorNotice?

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
            refreshError = await store.refreshCollections()
        }
        .alert(item: $refreshError) { notice in
            Alert(
                title: Text("Unable to refresh"),
                message: Text(notice.message),
                primaryButton: notice.recovery == .reconnect
                    ? .destructive(Text("Reconnect"), action: store.disconnect)
                    : .default(Text("Try again"), action: retryRefresh),
                secondaryButton: .cancel()
            )
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
            }

            LabeledContent("API key") {
                SecureField("Paste API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focusedField, equals: .apiKey)
                    .onSubmit(connect)
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
                            .accessibilityHidden(true)
                        Text("Connecting…")
                    }
                } else {
                    Text("Connect")
                }
            }
            .disabled(store.isConnecting)
            .accessibilityLabel(store.isConnecting ? "Connecting" : "Connect")
            .accessibilityValue(store.isConnecting ? "In progress" : "")
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
                Label {
                    Text(errorMessage)
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.red)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Error")
                .accessibilityValue(errorMessage)
            }
        }
    }

    private func retryRefresh() {
        Task { @MainActor in
            refreshError = await store.refreshCollections()
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
            case let .failed(notice):
                ContentUnavailableView {
                    Label("Unable to search documents", systemImage: "exclamationmark.circle")
                } description: {
                    Text(notice.message)
                } actions: {
                    if notice.recovery == .reconnect {
                        Button("Reconnect", action: store.disconnect)
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Try again") { request += 1 }
                            .buttonStyle(.borderedProminent)
                    }
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
                state = .failed(SessionErrorNotice(error: error))
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
        case failed(SessionErrorNotice)
    }
}
