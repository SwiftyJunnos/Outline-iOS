import OutlineCore
import SwiftUI

struct DocumentReaderView: View {
    let store: SessionStore
    let documentID: String
    let documentPath: String

    @State private var loadState = LoadState.loading
    @State private var loadRequest = 0

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                ProgressView("Loading document…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(document):
                DocumentContent(document: document)
            case let .failed(message):
                ContentUnavailableView {
                    Label("Unable to load document", systemImage: "exclamationmark.circle")
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
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadRequest) {
            await loadDocument()
        }
        .toolbar {
            if let webURL = store.webURL(for: documentPath) {
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: webURL) {
                        Label("Open in Outline", systemImage: "safari")
                    }
                }
            }
        }
    }

    private func loadDocument() async {
        loadState = .loading

        do {
            loadState = .loaded(try await store.document(id: documentID))
        } catch is CancellationError {
            return
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private enum LoadState {
        case loading
        case loaded(OutlineRichDocument)
        case failed(String)
    }
}

private struct DocumentContent: View {
    let document: OutlineRichDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(document.title)
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)

                ProseMirrorDocumentView(document: document)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .textSelection(.enabled)
    }
}
