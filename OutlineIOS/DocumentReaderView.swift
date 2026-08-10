import SwiftUI

struct DocumentReaderView: View {
    let store: SessionStore
    let documentID: String

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
        case loaded(OutlineDocument)
        case failed(String)
    }
}

private struct DocumentContent: View {
    let document: OutlineDocument

    private var bodyText: AttributedString {
        (try? AttributedString(markdown: document.text)) ?? AttributedString(document.text)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(document.title)
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)

                Text(bodyText)
                    .font(.body)
                    .lineSpacing(6)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity)
        }
    }
}
