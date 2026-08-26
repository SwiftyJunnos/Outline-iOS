import Foundation
import SwiftUI
import WebKit

struct SVGImageMetadata: Equatable {
    let aspectRatio: CGFloat?
}

func svgImageMetadata(_ data: Data) -> SVGImageMetadata? {
    let delegate = SVGMetadataParser()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.shouldProcessNamespaces = true
    parser.shouldResolveExternalEntities = false
    guard parser.parse() else { return nil }
    return delegate.metadata
}

private final class SVGMetadataParser: NSObject, XMLParserDelegate {
    private(set) var metadata: SVGImageMetadata?
    private var foundRoot = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        guard !foundRoot else { return }
        foundRoot = true
        guard elementName.caseInsensitiveCompare("svg") == .orderedSame else { return }
        metadata = SVGImageMetadata(aspectRatio: Self.aspectRatio(from: attributeDict["viewBox"]))
    }

    private static func aspectRatio(from viewBox: String?) -> CGFloat? {
        guard let values = viewBox?
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .compactMap({ Double($0) }),
            values.count == 4,
            values[2] > 0,
            values[3] > 0
        else {
            return nil
        }
        return values[2] / values[3]
    }
}

@MainActor
struct SVGImageView {
    let data: Data

    func makeWebView(coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        #elseif os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        return webView
    }

    func update(_ webView: WKWebView, coordinator: Coordinator) {
        guard coordinator.data != data else { return }
        coordinator.data = data
        webView.loadHTMLString(Self.html(for: data), baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private static func html(for data: Data) -> String {
        let source = data.base64EncodedString()
        return """
        <!doctype html>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
        <style>
          html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; }
          img { display: block; width: 100%; height: 100%; object-fit: contain; }
        </style>
        <img alt="" src="data:image/svg+xml;base64,\(source)">
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var data: Data?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            navigationAction.request.url?.scheme == "about" ? .allow : .cancel
        }
    }
}

#if os(iOS)
extension SVGImageView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let webView = makeWebView(coordinator: context.coordinator)
        update(webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        update(webView, coordinator: context.coordinator)
    }
}
#elseif os(macOS)
extension SVGImageView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let webView = makeWebView(coordinator: context.coordinator)
        update(webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        update(webView, coordinator: context.coordinator)
    }
}
#endif
