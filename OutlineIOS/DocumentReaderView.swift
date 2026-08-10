import OutlineCore
import SwiftUI

struct DocumentReaderView: View {
    let store: SessionStore
    let documentID: String
    let documentPath: String

    @State private var loadState = LoadState.loading
    @State private var loadRequest = 0
    @State private var linkTarget: DocumentLinkTarget?
    @State private var scrollTarget: String?
    @State private var scrollRequest = 0

    init(
        store: SessionStore,
        documentID: String,
        documentPath: String,
        anchor: String? = nil
    ) {
        self.store = store
        self.documentID = documentID
        self.documentPath = documentPath
        _scrollTarget = State(initialValue: anchor)
    }

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                ProgressView("Loading document…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(document):
                DocumentContent(
                    document: document,
                    store: store,
                    scrollTarget: scrollTarget,
                    scrollRequest: scrollRequest,
                    onOpenURL: openURL,
                    onRefresh: { await loadDocument(showLoading: false) }
                )
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
        .navigationDestination(item: $linkTarget) { target in
            DocumentReaderView(
                store: store,
                documentID: target.documentID,
                documentPath: target.documentPath,
                anchor: target.anchor
            )
        }
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

    private func openURL(_ url: URL) -> OpenURLAction.Result {
        guard
            let baseURL = store.connectedServerURL,
            let target = documentLinkTarget(from: url, serverURL: baseURL)
        else {
            return .systemAction
        }

        if target.documentID == documentID
            || target.documentID == documentIdentifier(from: documentPath, serverURL: baseURL) {
            if let anchor = target.anchor {
                scrollTarget = anchor
                scrollRequest += 1
            }
        } else {
            linkTarget = target
        }
        return .handled
    }

    private func loadDocument(showLoading: Bool = true) async {
        if showLoading {
            loadState = .loading
        }

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
    let store: SessionStore
    let scrollTarget: String?
    let scrollRequest: Int
    let onOpenURL: (URL) -> OpenURLAction.Result
    let onRefresh: @MainActor @Sendable () async -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(document.title)
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)

                    ProseMirrorDocumentView(
                        document: document,
                        baseURL: store.webURL(for: document.url),
                        assetLoader: { source in
                            try await store.assetData(for: source)
                        }
                    )
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding()
                .frame(maxWidth: .infinity)
            }
            .refreshable(action: onRefresh)
            .task(id: scrollRequest) {
                guard let scrollTarget else { return }
                await Task.yield()
                withAnimation {
                    proxy.scrollTo(scrollTarget, anchor: .top)
                }
            }
        }
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction(handler: onOpenURL))
    }
}

struct DocumentLinkTarget: Hashable, Identifiable {
    let documentID: String
    let documentPath: String
    let anchor: String?

    var id: String {
        "\(documentID)#\(anchor ?? "")"
    }
}

func documentLinkTarget(from url: URL, serverURL: URL) -> DocumentLinkTarget? {
    guard sameOrigin(url, serverURL) else { return nil }
    let components = url.pathComponents.filter { $0 != "/" }
    guard
        let docIndex = components.firstIndex(of: "doc"),
        components.indices.contains(docIndex + 1)
    else {
        return nil
    }

    let documentID = components[docIndex + 1]
    guard !documentID.isEmpty else { return nil }
    return DocumentLinkTarget(
        documentID: documentID,
        documentPath: url.path,
        anchor: url.fragment?.removingPercentEncoding
    )
}

private func documentIdentifier(from path: String, serverURL: URL) -> String? {
    guard let url = URL(string: path, relativeTo: serverURL)?.absoluteURL else { return nil }
    return documentLinkTarget(from: url, serverURL: serverURL)?.documentID
}

private func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
        && lhs.host?.lowercased() == rhs.host?.lowercased()
        && (lhs.port ?? 443) == (rhs.port ?? 443)
}
