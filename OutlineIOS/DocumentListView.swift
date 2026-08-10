import SwiftUI

struct DocumentListView: View {
    let store: SessionStore
    let collection: OutlineCollection

    @State private var loadState = LoadState.loading
    @State private var loadRequest = 0

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
                                DocumentReaderView(store: store, documentID: document.id)
                            } label: {
                                Text(document.title)
                            }
                        }
                    }
                }
            case let .failed(message):
                ContentUnavailableView {
                    Label("Unable to load documents", systemImage: "exclamationmark.circle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") {
                        loadRequest += 1
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadRequest) {
            await loadDocuments()
        }
    }

    private func loadDocuments() async {
        loadState = .loading

        do {
            loadState = .loaded(try await store.documents(in: collection.id))
        } catch is CancellationError {
            return
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private enum LoadState {
        case loading
        case loaded([OutlineDocumentNode])
        case failed(String)
    }
}
