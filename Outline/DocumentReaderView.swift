import OutlineCore
import SwiftUI

struct DocumentReaderView: View {
    let store: SessionStore
    let documentID: String
    let documentPath: String

    @State private var loadState = LoadState.loading
    @State private var loadRequest = 0
    @State private var errorAlert: DocumentReaderAlert?
    @State private var linkTarget: DocumentLinkTarget?
    @State private var scrollTarget: String?
    @State private var scrollRequest = 0
    @State private var isShowingComments = false

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
                    errorAlert: $errorAlert,
                    onOpenURL: openURL,
                    onRefresh: {
                        await loadDocument(showLoading: false)
                    },
                    onAssetError: { notice in
                        guard notice.recovery == .reconnect else { return }
                        errorAlert = DocumentReaderAlert(title: "Unable to load media", notice: notice)
                    }
                )
            case let .failed(notice):
                ContentUnavailableView {
                    Label("Unable to load document", systemImage: "exclamationmark.circle")
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
            _ = await loadDocument()
        }
        .alert(item: $errorAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.notice.message),
                primaryButton: alert.notice.recovery == .reconnect
                    ? .destructive(Text("Reconnect"), action: store.disconnect)
                    : .default(Text("Try again"), action: retryRefresh),
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $isShowingComments) {
            CommentsView(
                store: store,
                documentID: documentID,
                documentURL: store.webURL(for: documentPath)
            )
            .presentationDetents([.medium, .large])
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingComments = true
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right")
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Comments")
                .accessibilityHint("Shows comments for this document")
            }
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

    private func loadDocument(showLoading: Bool = true) async -> SessionErrorNotice? {
        if showLoading {
            loadState = .loading
        }

        do {
            loadState = .loaded(try await store.document(id: documentID))
            return nil
        } catch is CancellationError {
            return nil
        } catch {
            let notice = SessionErrorNotice(error: error)
            if showLoading {
                loadState = .failed(notice)
            }
            return notice
        }
    }

    private func retryRefresh() {
        Task { @MainActor in
            if let notice = await loadDocument(showLoading: false) {
                errorAlert = DocumentReaderAlert(title: "Unable to refresh", notice: notice)
            }
        }
    }

    private enum LoadState {
        case loading
        case loaded(OutlineRichDocument)
        case failed(SessionErrorNotice)
    }

}

private struct DocumentReaderAlert: Identifiable {
    let title: String
    let notice: SessionErrorNotice

    var id: String {
        "\(title):\(notice.id)"
    }
}

private struct DocumentContent: View {
    let document: OutlineRichDocument
    let store: SessionStore
    let scrollTarget: String?
    let scrollRequest: Int
    @Binding var errorAlert: DocumentReaderAlert?
    let onOpenURL: (URL) -> OpenURLAction.Result
    let onRefresh: @MainActor @Sendable () async -> SessionErrorNotice?
    let onAssetError: @MainActor @Sendable (SessionErrorNotice) -> Void

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
                            do {
                                return try await store.assetData(for: source)
                            } catch {
                                await onAssetError(SessionErrorNotice(error: error))
                                throw error
                            }
                        }
                    )
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding()
                .frame(maxWidth: .infinity)
            }
            .refreshable {
                if let notice = await onRefresh() {
                    errorAlert = DocumentReaderAlert(title: "Unable to refresh", notice: notice)
                }
            }
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
