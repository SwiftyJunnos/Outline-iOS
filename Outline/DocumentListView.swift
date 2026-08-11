import OSLog
import SwiftUI

private let documentListLogger = Logger(subsystem: "house.junnos.outlineios", category: "Documents")

struct DocumentListView: View {
    let store: SessionStore
    let collection: OutlineCollection

    @State private var loadState = LoadState.loading
    @State private var loadRequest = 0
    @State private var refreshError: SessionErrorNotice?

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                ProgressView("Loading documents…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(documents):
                if documents.isEmpty {
                    ContentUnavailableView(
                        "No documents",
                        systemImage: "doc.text",
                        description: Text("Add a document to this collection in Outline to see it here.")
                    )
                } else {
                    List {
                        OutlineGroup(documents, children: \.outlineChildren) { document in
                            NavigationLink {
                                DocumentReaderView(
                                    store: store,
                                    documentID: document.id,
                                    documentPath: document.url
                                )
                            } label: {
                                Text(document.title)
                            }
                        }
                    }
                }
            case let .failed(notice):
                ContentUnavailableView {
                    Label("Unable to load documents", systemImage: "exclamationmark.circle")
                } description: {
                    Text(notice.message)
                } actions: {
                    if notice.recovery == .reconnect {
                        Button("Reconnect", action: store.disconnect)
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Try again") {
                            loadRequest += 1
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadRequest) {
            _ = await loadDocuments()
        }
        .refreshable {
            refreshError = await loadDocuments(showLoading: false)
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

    private func loadDocuments(showLoading: Bool = true) async -> SessionErrorNotice? {
        if showLoading {
            loadState = .loading
        }
        do {
            loadState = .loaded(try await store.documents(in: collection.id))
            return nil
        } catch is CancellationError {
            return nil
        } catch {
            documentListLogger.error(
                "Unable to load documents for collection \(collection.id, privacy: .private): \(error.localizedDescription, privacy: .public)"
            )
            let notice = SessionErrorNotice(error: error)
            if showLoading {
                loadState = .failed(notice)
            }
            return notice
        }
    }

    private func retryRefresh() {
        Task { @MainActor in
            refreshError = await loadDocuments(showLoading: false)
        }
    }

    private enum LoadState {
        case loading
        case loaded([OutlineDocumentNode])
        case failed(SessionErrorNotice)
    }
}
