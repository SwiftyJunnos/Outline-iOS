import Foundation
import SwiftUI
import WebKit

struct MermaidDiagramView: View {
    let source: String

    private let allowsFullScreen: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var height: CGFloat = 160
    @State private var errorMessage: String?
    @State private var renderedSignature: String?
    @State private var isFullScreenPresented = false

    init(source: String, allowsFullScreen: Bool = true) {
        self.source = source
        self.allowsFullScreen = allowsFullScreen
    }

    var body: some View {
        Group {
            if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Unable to render Mermaid diagram", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        Text(source)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            } else if allowsFullScreen, renderedSignature == renderSignature {
                diagram
                    .overlay {
                        Button {
                            isFullScreenPresented = true
                        } label: {
                            Color.clear
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open Mermaid diagram in full screen")
                        .accessibilityHint("Opens zoom and pan controls")
                    }
                    .mediaViewerCover(isPresented: $isFullScreenPresented) {
                        MermaidFullScreenView(source: source)
                    }
            } else {
                diagram
                    .accessibilityLabel("Mermaid diagram")
            }
        }
    }

    private var renderSignature: String {
        "\(colorScheme == .dark):\(source)"
    }

    private var diagram: some View {
        MermaidWebView(
            source: source,
            darkMode: colorScheme == .dark,
            allowsZoom: false,
            onHeightChange: {
                height = max(1, $0)
                renderedSignature = renderSignature
            },
            onError: {
                renderedSignature = nil
                errorMessage = $0
            }
        )
        .frame(height: height)
        .allowsHitTesting(false)
    }
}

private struct MermaidFullScreenView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let source: String

    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            (colorScheme == .dark ? Color.black : Color.white).ignoresSafeArea()

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.primary)
                    .padding()
            } else {
                MermaidWebView(
                    source: source,
                    darkMode: colorScheme == .dark,
                    allowsZoom: true,
                    onHeightChange: { _ in },
                    onError: { errorMessage = $0 }
                )
                .ignoresSafeArea()
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .background(.thinMaterial, in: Circle())
            .accessibilityLabel("Close viewer")
            .padding()
        }
    }
}

@MainActor
private struct MermaidWebView {
    let source: String
    let darkMode: Bool
    let allowsZoom: Bool
    let onHeightChange: (CGFloat) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onHeightChange: onHeightChange, onError: onError)
    }

    func makeWebView(coordinator: Coordinator) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(coordinator, name: "mermaid")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        #if os(iOS)
        configuration.ignoresViewportScaleLimits = allowsZoom
        #endif
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        #if os(iOS)
        webView.isOpaque = true
        webView.backgroundColor = darkMode ? .black : .white
        webView.scrollView.isScrollEnabled = allowsZoom
        webView.scrollView.minimumZoomScale = 1
        webView.scrollView.maximumZoomScale = allowsZoom ? 8 : 1
        webView.scrollView.pinchGestureRecognizer?.isEnabled = allowsZoom
        webView.scrollView.bouncesZoom = allowsZoom
        webView.scrollView.backgroundColor = darkMode ? .black : .white
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.showsVerticalScrollIndicator = false
        #endif
        return webView
    }

    func update(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.onHeightChange = onHeightChange
        coordinator.onError = onError

        let signature = "\(darkMode):\(source)"
        guard coordinator.signature != signature else { return }
        coordinator.signature = signature

        do {
            coordinator.renderScript = try Self.renderScript(
                source: source,
                darkMode: darkMode,
                allowsZoom: allowsZoom
            )
            let page = try Self.pageURL()
            webView.loadFileURL(page.url, allowingReadAccessTo: page.readAccessURL)
        } catch {
            onError(error.localizedDescription)
        }
    }

    private static func pageURL() throws -> (url: URL, readAccessURL: URL) {
        guard
            let rendererURL = Bundle.module.url(
                forResource: "mermaid-renderer",
                withExtension: "html"
            ),
            Bundle.module.url(
                forResource: "mermaid-11.12.0.min",
                withExtension: "js"
            ) != nil
        else {
            throw MermaidError.missingRuntime
        }
        return (rendererURL, rendererURL.deletingLastPathComponent())
    }

    private static func renderScript(
        source: String,
        darkMode: Bool,
        allowsZoom: Bool
    ) throws -> String {
        let payload = try JSONSerialization.data(withJSONObject: [
            "source": source,
            "darkMode": darkMode,
            "allowsZoom": allowsZoom,
        ])
        guard let json = String(data: payload, encoding: .utf8) else {
            throw MermaidError.missingRuntime
        }
        return "void window.renderMermaid(\(json)); true"
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var signature: String?
        var lastHeight: CGFloat?
        var renderScript: String?
        var onHeightChange: (CGFloat) -> Void
        var onError: (String) -> Void

        init(
            onHeightChange: @escaping (CGFloat) -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.onHeightChange = onHeightChange
            self.onError = onError
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let payload = message.body as? [String: Any] else { return }
            if let error = payload["error"] as? String {
                onError(error)
            } else if let height = payload["height"] as? NSNumber {
                let height = CGFloat(truncating: height)
                guard height != lastHeight else { return }
                lastHeight = height
                onHeightChange(height)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            guard let renderScript else { return }
            webView.evaluateJavaScript(renderScript) { [weak self] _, error in
                if let error {
                    self?.onError(error.localizedDescription)
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            return url.scheme == "about" || url.isFileURL ? .allow : .cancel
        }
    }

    private enum MermaidError: LocalizedError {
        case missingRuntime

        var errorDescription: String? {
            "The bundled Mermaid renderer is unavailable."
        }
    }
}

#if os(iOS)
extension MermaidWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let webView = makeWebView(coordinator: context.coordinator)
        update(webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        update(webView, coordinator: context.coordinator)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mermaid")
    }
}
#elseif os(macOS)
extension MermaidWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let webView = makeWebView(coordinator: context.coordinator)
        update(webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        update(webView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mermaid")
    }
}
#endif
