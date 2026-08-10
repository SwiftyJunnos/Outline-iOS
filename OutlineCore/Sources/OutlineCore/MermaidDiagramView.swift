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
            Color.black.ignoresSafeArea()

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.white)
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
            .foregroundStyle(.white)
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
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = allowsZoom
        webView.scrollView.minimumZoomScale = 1
        webView.scrollView.maximumZoomScale = allowsZoom ? 8 : 1
        webView.scrollView.pinchGestureRecognizer?.isEnabled = allowsZoom
        webView.scrollView.bouncesZoom = allowsZoom
        webView.scrollView.backgroundColor = .clear
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
            webView.loadHTMLString(
                try Self.html(source: source, darkMode: darkMode, allowsZoom: allowsZoom),
                baseURL: nil
            )
        } catch {
            onError(error.localizedDescription)
        }
    }

    private static func html(source: String, darkMode: Bool, allowsZoom: Bool) throws -> String {
        guard
            let scriptURL = Bundle.module.url(
                forResource: "mermaid-11.12.0.min",
                withExtension: "js"
            )
        else {
            throw MermaidError.missingRuntime
        }

        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        let encodedSource = Data(source.utf8).base64EncodedString()
        let theme = darkMode ? "dark" : "default"
        let background = darkMode ? "#000000" : "#ffffff"
        let viewport = allowsZoom
            ? "width=device-width, initial-scale=1, minimum-scale=1, maximum-scale=8, user-scalable=yes"
            : "width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"
        let overflow = allowsZoom ? "auto" : "hidden"
        let diagramCSS = allowsZoom
            ? """
              #diagram { display: flex; justify-content: center; align-items: center; min-height: 100vh; width: 100%; padding: 16px; box-sizing: border-box; }
              #diagram svg { display: block; max-width: none !important; width: auto !important; height: auto !important; }
              """
            : """
              #diagram { display: flex; justify-content: center; width: 100%; }
              #diagram svg { display: block; width: 100%; height: auto; max-width: 100%; }
              """

        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="\(viewport)">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:">
          <style>
            html, body { margin: 0; padding: 0; background: \(background); overflow: \(overflow); \(allowsZoom ? "min-height: 100vh;" : "") }
            \(diagramCSS)
          </style>
        </head>
        <body>
          <div id="diagram" role="img" aria-label="Mermaid diagram"></div>
          <script>\(script)</script>
          <script>
            const bytes = Uint8Array.from(atob('\(encodedSource)'), c => c.charCodeAt(0));
            const source = new TextDecoder().decode(bytes);
            const diagram = document.getElementById('diagram');
            const reportHeight = () => {
              const height = Math.ceil(diagram.getBoundingClientRect().height);
              window.webkit.messageHandlers.mermaid.postMessage({ height });
            };
            (async () => {
              try {
                mermaid.initialize({
                  startOnLoad: false,
                  securityLevel: 'strict',
                  suppressErrorRendering: true,
                  theme: '\(theme)'
                });
                const result = await mermaid.render('mermaid-diagram', source);
                diagram.innerHTML = result.svg;
                result.bindFunctions?.(diagram);
                new ResizeObserver(reportHeight).observe(diagram);
                requestAnimationFrame(reportHeight);
              } catch (error) {
                window.webkit.messageHandlers.mermaid.postMessage({
                  error: error instanceof Error ? error.message : String(error)
                });
              }
            })();
          </script>
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var signature: String?
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
                onHeightChange(CGFloat(truncating: height))
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            navigationAction.request.url?.scheme == "about" ? .allow : .cancel
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
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mermaid")
    }
}
#endif
