import Foundation
import SwiftUI
import QuickLook

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public typealias ProseMirrorAssetLoader = @Sendable (String) async throws -> Data

public struct ProseMirrorDocumentView: View {
    private let document: OutlineRichDocument
    private let baseURL: URL?
    private let assetLoader: ProseMirrorAssetLoader?

    public init(document: OutlineRichDocument) {
        self.init(document: document, baseURL: nil, assetLoader: nil)
    }

    public init(
        document: OutlineRichDocument,
        baseURL: URL? = nil,
        assetLoader: ProseMirrorAssetLoader? = nil
    ) {
        self.document = document
        self.baseURL = baseURL
        self.assetLoader = assetLoader
    }

    public var body: some View {
        ProseMirrorBlock(
            node: document.data,
            baseURL: baseURL,
            assetLoader: assetLoader,
            headingAnchors: outlineHeadingAnchors(in: document.data),
            nodePath: []
        )
    }
}

private struct ProseMirrorBlock: View {
    let node: ProseMirrorNode
    let baseURL: URL?
    let assetLoader: ProseMirrorAssetLoader?
    let headingAnchors: [[Int]: String]
    let nodePath: [Int]

    var body: some View {
        switch node.type {
        case "doc":
            blocks(node.content)
        case "paragraph":
            ParagraphBlock(node: node, baseURL: baseURL, assetLoader: assetLoader)
        case "heading":
            heading
        case "bullet_list", "checkbox_list":
            list(ordered: false)
        case "ordered_list":
            list(ordered: true)
        case "list_item", "checkbox_item":
            blocks(node.content)
        case "blockquote":
            blocks(node.content)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.secondary).frame(width: 3)
                }
        case "code_block", "code_fence":
            if isMermaidCodeBlock(node) {
                MermaidDiagramView(source: plainText(node))
            } else {
                CodeBlockView(node: node)
            }
        case "horizontal_rule", "hr":
            Divider()
        case "hard_break":
            Text("\n")
        case "table":
            TableBlock(
                node: node,
                baseURL: baseURL,
                assetLoader: assetLoader,
                headingAnchors: headingAnchors,
                nodePath: nodePath
            )
        case "container_notice":
            NoticeBlock(
                node: node,
                baseURL: baseURL,
                assetLoader: assetLoader,
                headingAnchors: headingAnchors,
                nodePath: nodePath
            )
        case "container_toggle":
            ToggleBlock(
                node: node,
                baseURL: baseURL,
                assetLoader: assetLoader,
                headingAnchors: headingAnchors,
                nodePath: nodePath
            )
        case "attachment":
            DownloadableMediaBlock(
                node: node,
                sourceKey: "href",
                icon: "paperclip",
                fallbackTitle: "Attachment",
                baseURL: baseURL,
                assetLoader: assetLoader
            )
        case "embed", "bookmark", "link_preview":
            LinkedMediaBlock(node: node, sourceKey: "href", icon: "bookmark", baseURL: baseURL)
        case "video":
            DownloadableMediaBlock(
                node: node,
                sourceKey: "src",
                icon: "play.rectangle",
                fallbackTitle: "Video",
                baseURL: baseURL,
                assetLoader: assetLoader
            )
        case "math_block":
            MathBlock(node: node)
        case "image":
            ImageBlock(node: node, assetLoader: assetLoader)
        case "tr", "th", "td":
            blocks(node.content)
        default:
            UnsupportedBlock(type: node.type)
        }
    }

    @ViewBuilder
    private func blocks(_ nodes: [ProseMirrorNode]) -> some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(Array(nodes.enumerated()), id: \.offset) { index, child in
                anchoredBlock(
                    node: child,
                    baseURL: baseURL,
                    assetLoader: assetLoader,
                    headingAnchors: headingAnchors,
                    nodePath: nodePath + [index]
                )
            }
        }
    }

    @ViewBuilder
    private func list(ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(node.content.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(marker(for: item, index: index, ordered: ordered))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    anchoredBlock(
                        node: item,
                        baseURL: baseURL,
                        assetLoader: assetLoader,
                        headingAnchors: headingAnchors,
                        nodePath: nodePath + [index]
                    )
                }
            }
        }
    }

    private func marker(for item: ProseMirrorNode, index: Int, ordered: Bool) -> String {
        if node.type == "checkbox_list" {
            return item.boolAttribute("checked") == true ? "☑" : "☐"
        }
        return ordered ? "\((node.intAttribute("order") ?? 1) + index)." : "•"
    }

    private var heading: some View {
        Text(inlineText(node, baseURL: baseURL))
            .font(headingFont)
            .accessibilityAddTraits(.isHeader)
    }

    private var headingFont: Font {
        switch node.intAttribute("level") ?? 1 {
        case 1: .title.bold()
        case 2: .title2.bold()
        default: .title3.bold()
        }
    }
}

@ViewBuilder
private func anchoredBlock(
    node: ProseMirrorNode,
    baseURL: URL?,
    assetLoader: ProseMirrorAssetLoader?,
    headingAnchors: [[Int]: String],
    nodePath: [Int]
) -> some View {
    if let anchor = headingAnchors[nodePath] {
        ProseMirrorBlock(
            node: node,
            baseURL: baseURL,
            assetLoader: assetLoader,
            headingAnchors: headingAnchors,
            nodePath: nodePath
        )
        .id(anchor)
    } else {
        ProseMirrorBlock(
            node: node,
            baseURL: baseURL,
            assetLoader: assetLoader,
            headingAnchors: headingAnchors,
            nodePath: nodePath
        )
    }
}

func isMermaidCodeBlock(_ node: ProseMirrorNode) -> Bool {
    ["code_block", "code_fence"].contains(node.type)
        && node.stringAttribute("language")?.lowercased() == "mermaid"
}

func outlineHeadingAnchors(in root: ProseMirrorNode) -> [[Int]: String] {
    var anchors: [[Int]: String] = [:]
    var seen: [String: Int] = [:]

    func visit(_ node: ProseMirrorNode, path: [Int]) {
        if node.type == "heading" {
            let base = outlineHeadingAnchor(plainText(node))
            let duplicateIndex = seen[base, default: 0]
            anchors[path] = duplicateIndex == 0 ? base : "\(base)-\(duplicateIndex)"
            seen[base] = duplicateIndex + 1
        }
        for (index, child) in node.content.enumerated() {
            visit(child, path: path + [index])
        }
    }

    visit(root, path: [])
    return anchors
}

private let outlineSlugCharacterMap: [String: String] = {
    let url = Bundle.module.url(
        forResource: "slugify-1.6.9-charmap",
        withExtension: "json"
    )!
    return try! JSONDecoder().decode(
        [String: String].self,
        from: Data(contentsOf: url)
    )
}()

private let outlineSlugRemovableCharacters = CharacterSet(
    charactersIn: "!\"#$%&'.()*+,/:;<=>?@[\\]^_`{|}~"
)

private func outlineHeadingAnchor(_ text: String) -> String {
    var slug = ""
    for character in text.precomposedStringWithCanonicalMapping {
        let mapped = outlineSlugCharacterMap[String(character)] ?? String(character)
        slug += mapped == "-" ? " " : mapped
    }

    var sanitized = ""
    for scalar in slug.unicodeScalars
        where !outlineSlugRemovableCharacters.contains(scalar) {
        sanitized.unicodeScalars.append(scalar)
    }

    return "h-" + sanitized
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: "-")
        .lowercased()
}

private struct CodeBlockView: View {
    let node: ProseMirrorNode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let language = normalizedCodeLanguage(node.stringAttribute("language")) {
                Text(language.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                Text(highlightedCode(plainText(node), language: node.stringAttribute("language")))
                    .font(.body.monospaced())
                    .padding(12)
            }
        }
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

func normalizedCodeLanguage(_ language: String?) -> String? {
    guard let language = language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
          !language.isEmpty else { return nil }
    switch language {
    case "js", "jsx": return "javascript"
    case "ts", "tsx": return "typescript"
    case "py": return "python"
    case "sh", "zsh", "bash": return "shell"
    default: return language
    }
}

func highlightedCode(_ source: String, language: String?) -> AttributedString {
    var output = AttributedString(source)
    guard let language = normalizedCodeLanguage(language),
          let keywords = codeKeywords[language] else { return output }

    if !keywords.isEmpty {
        applyCodeStyle(#"\b(?:\#(keywords.sorted().joined(separator: "|")))\b"#, color: .blue, source: source, output: &output)
    }
    applyCodeStyle(#"\b\d+(?:\.\d+)?\b"#, color: .purple, source: source, output: &output)
    applyCodeStyle(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, color: .red, source: source, output: &output)
    let commentPattern = ["python", "shell", "yaml"].contains(language) ? #"(?m)#.*$"# : #"(?m)//.*$"#
    applyCodeStyle(commentPattern, color: .green, source: source, output: &output)
    return output
}

private let codeKeywords: [String: Set<String>] = [
    "swift": ["actor", "class", "else", "enum", "extension", "func", "guard", "if", "import", "let", "protocol", "return", "struct", "switch", "var"],
    "javascript": ["async", "await", "class", "const", "else", "export", "function", "if", "import", "let", "return", "var"],
    "typescript": ["async", "await", "class", "const", "else", "enum", "export", "function", "if", "import", "interface", "return", "type", "let"],
    "python": ["async", "await", "class", "def", "elif", "else", "for", "from", "if", "import", "in", "return", "while"],
    "shell": ["case", "do", "done", "elif", "else", "esac", "fi", "for", "function", "if", "in", "then", "while"],
    "json": [],
    "yaml": ["false", "null", "true"],
]

private func applyCodeStyle(
    _ pattern: String,
    color: Color,
    source: String,
    output: inout AttributedString
) {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
    for match in expression.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
        guard let sourceRange = Range(match.range, in: source),
              let lowerBound = AttributedString.Index(sourceRange.lowerBound, within: output),
              let upperBound = AttributedString.Index(sourceRange.upperBound, within: output) else { continue }
        output[lowerBound..<upperBound].foregroundColor = color
    }
}

private struct ParagraphBlock: View {
    let node: ProseMirrorNode
    let baseURL: URL?
    let assetLoader: ProseMirrorAssetLoader?

    var body: some View {
        if node.content.contains(where: { $0.type == "image" }) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(node.content.enumerated()), id: \.offset) { _, child in
                    if child.type == "image" {
                        ImageBlock(node: child, assetLoader: assetLoader)
                    } else {
                        Text(inlineText(ProseMirrorNode(type: "paragraph", content: [child]), baseURL: baseURL))
                    }
                }
            }
        } else {
            Text(inlineText(node, baseURL: baseURL))
                .font(.body)
                .lineSpacing(6)
                .accessibilityLabel(accessibilityLabel)
        }
    }

    private var accessibilityLabel: String {
        let text = String(inlineText(node, baseURL: baseURL).characters)
        return hasUnresolvedComment ? "\(text), has unresolved comment" : text
    }

    private var hasUnresolvedComment: Bool {
        node.content.flatMap(\.marks).contains {
            $0.type == "comment" && $0.attrs["resolved"]?.boolValue != true
        }
    }
}

private struct TableBlock: View {
    let node: ProseMirrorNode
    let baseURL: URL?
    let assetLoader: ProseMirrorAssetLoader?
    let headingAnchors: [[Int]: String]
    let nodePath: [Int]

    var body: some View {
        ScrollView(.horizontal) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(node.content.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(row.content.enumerated()), id: \.offset) { cellIndex, cell in
                            cellView(cell, rowIndex: rowIndex, cellIndex: cellIndex)
                                .gridCellColumns(max(1, cell.intAttribute("colspan") ?? 1))
                        }
                    }
                }
            }
            .overlay { Rectangle().stroke(.quaternary) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Table")
    }

    private func cellView(_ cell: ProseMirrorNode, rowIndex: Int, cellIndex: Int) -> some View {
        anchoredBlock(
            node: cell,
            baseURL: baseURL,
            assetLoader: assetLoader,
            headingAnchors: headingAnchors,
            nodePath: nodePath + [rowIndex, cellIndex]
        )
            .font(cell.type == "th" ? .body.bold() : .body)
            .frame(minWidth: 120, maxWidth: 280, alignment: alignment(cell))
            .padding(10)
            .background(cell.type == "th" ? Color.secondary.opacity(0.12) : .clear)
            .overlay { Rectangle().stroke(Color.secondary.opacity(0.25), lineWidth: 0.5) }
            .accessibilityAddTraits(cell.type == "th" ? .isHeader : [])
    }

    private func alignment(_ cell: ProseMirrorNode) -> Alignment {
        switch cell.stringAttribute("alignment") {
        case "center": .center
        case "right": .trailing
        default: .leading
        }
    }
}

private struct NoticeBlock: View {
    let node: ProseMirrorNode
    let baseURL: URL?
    let assetLoader: ProseMirrorAssetLoader?
    let headingAnchors: [[Int]: String]
    let nodePath: [Int]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(node.content.enumerated()), id: \.offset) { index, child in
                    anchoredBlock(
                        node: child,
                        baseURL: baseURL,
                        assetLoader: assetLoader,
                        headingAnchors: headingAnchors,
                        nodePath: nodePath + [index]
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(style.capitalized) notice")
    }

    private var style: String { node.stringAttribute("style") ?? "info" }
    private var icon: String {
        switch style {
        case "success": "checkmark.circle"
        case "tip": "star"
        case "warning": "exclamationmark.triangle"
        default: "info.circle"
        }
    }
    private var tint: Color {
        switch style {
        case "success": .green
        case "tip": .purple
        case "warning": .orange
        default: .blue
        }
    }
}

private struct ToggleBlock: View {
    let node: ProseMirrorNode
    let baseURL: URL?
    let assetLoader: ProseMirrorAssetLoader?
    let headingAnchors: [[Int]: String]
    let nodePath: [Int]
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(node.content.dropFirst().enumerated()), id: \.offset) { index, child in
                    anchoredBlock(
                        node: child,
                        baseURL: baseURL,
                        assetLoader: assetLoader,
                        headingAnchors: headingAnchors,
                        nodePath: nodePath + [index + 1]
                    )
                }
            }
            .padding(.top, 8)
        } label: {
            Text(node.content.first.map { inlineText($0, baseURL: baseURL) } ?? AttributedString("Details"))
                .font(.headline)
        }
    }
}

private struct DownloadableMediaBlock: View {
    let node: ProseMirrorNode
    let sourceKey: String
    let icon: String
    let fallbackTitle: String
    let baseURL: URL?
    let assetLoader: ProseMirrorAssetLoader?

    @State private var previewURL: URL?
    @State private var errorMessage: String?
    @State private var request = 0
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if assetLoader != nil, source != nil {
                    Button {
                        request += 1
                    } label: {
                        card
                    }
                    .disabled(isLoading)
                } else if let url = resolvedSafeURL(source, baseURL: baseURL) {
                    Link(destination: url) { card }
                } else {
                    card
                }
            }
            .buttonStyle(.plain)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .quickLookPreview($previewURL)
        .task(id: request) {
            guard request > 0 else { return }
            await downloadAndOpen()
        }
        .onDisappear {
            removePreviewFile()
        }
    }

    private var source: String? {
        let source = node.stringAttribute(sourceKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return source?.isEmpty == false ? source : nil
    }

    private var title: String {
        let title = node.stringAttribute("title")?.trimmingCharacters(in: .whitespacesAndNewlines)
        return title?.isEmpty == false ? title! : fallbackTitle
    }

    private var card: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.title3).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(2)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: assetLoader == nil ? "arrow.up.right" : "arrow.down.circle")
                    .accessibilityHidden(true)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private var detail: String? {
        if node.type == "attachment" {
            return attachmentDetail(node)
        }
        guard let url = resolvedSafeURL(source, baseURL: baseURL) else { return "Link unavailable" }
        return url.host ?? url.absoluteString
    }

    @MainActor
    private func downloadAndOpen() async {
        guard let source, let assetLoader else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var temporaryURL: URL?
        do {
            let data = try await assetLoader(source)
            try Task.checkCancellation()
            let filename = safeAttachmentFilename(
                title,
                fallbackExtension: URL(string: source, relativeTo: baseURL)?.pathExtension
            )
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString)-\(filename)")
            try data.write(to: url, options: .atomic)
            temporaryURL = url
            try Task.checkCancellation()
            removePreviewFile()
            previewURL = url
            temporaryURL = nil
        } catch is CancellationError {
            if let temporaryURL {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        } catch {
            if let temporaryURL {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
            errorMessage = error.localizedDescription
        }
    }
    @MainActor
    private func removePreviewFile() {
        guard let previewURL else { return }
        try? FileManager.default.removeItem(at: previewURL)
        self.previewURL = nil
    }
}

private struct LinkedMediaBlock: View {
    let node: ProseMirrorNode
    let sourceKey: String
    let icon: String
    let baseURL: URL?

    var body: some View {
        let title = node.stringAttribute("title") ?? (node.type == "video" ? "Video" : "Embedded content")
        Group {
            if let url = resolvedSafeURL(node.stringAttribute(sourceKey), baseURL: baseURL) {
                Link(destination: url) { card(title: title, detail: url.host ?? url.absoluteString) }
            } else {
                card(title: title, detail: "Link unavailable")
            }
        }
        .buttonStyle(.plain)
    }

    private func card(title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.title3).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.right").accessibilityHidden(true)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}

private struct MathBlock: View {
    let node: ProseMirrorNode

    var body: some View {
        ScrollView(.horizontal) {
            Text(plainText(node)).font(.body.monospaced()).padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("Math: \(plainText(node))")
    }
}

private struct ImageBlock: View {
    let node: ProseMirrorNode
    let assetLoader: ProseMirrorAssetLoader?
    @State private var image: Image?
    @State private var errorMessage: String?
    @State private var request = 0
    @State private var isViewerPresented = false

    var body: some View {
        Group {
            if let image {
                Button {
                    isViewerPresented = true
                } label: {
                    image
                        .resizable()
                        .scaledToFit()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View \(altText) full screen")
                .accessibilityHint("Opens a full-screen viewer with zoom and pan controls")
                .mediaViewerCover(isPresented: $isViewerPresented) {
                    ZoomableMediaViewer(accessibilityName: altText) {
                        image
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 32)
                            .overlay(.black.opacity(0.2))
                    } content: {
                        image.resizable().scaledToFit()
                    }
                }
            } else if assetLoader == nil || source == nil {
                Label(altText, systemImage: "photo")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel(altText)
            } else if let errorMessage {
                VStack(spacing: 8) {
                    Label(altText, systemImage: "photo").foregroundStyle(.secondary)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try again") { request += 1 }
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel(altText)
            } else {
                ProgressView("Loading image…")
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .accessibilityLabel(altText)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .task(id: request) { await load() }
    }

    private var source: String? {
        let value = node.stringAttribute("src")?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private var altText: String {
        let value = node.stringAttribute("alt")?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value! : "Image"
    }

    private var aspectRatio: CGFloat? {
        guard let width = node.doubleAttribute("width"), let height = node.doubleAttribute("height"), height > 0 else {
            return nil
        }
        return width / height
    }

    @MainActor
    private func load() async {
        guard let source, let assetLoader else { return }
        errorMessage = nil
        do {
            let loadedData = try await assetLoader(source)
            guard let loadedImage = try await platformImage(data: loadedData) else {
                errorMessage = "The image format is not supported."
                return
            }
            image = loadedImage
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct UnsupportedBlock: View {
    let type: String

    var body: some View {
        Label("Unsupported \(type) block — open in Outline to view", systemImage: "doc.badge.ellipsis")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

func inlineText(_ parent: ProseMirrorNode, baseURL: URL? = nil) -> AttributedString {
    parent.content.reduce(into: AttributedString()) { output, child in
        if child.type == "hard_break" {
            output.append(AttributedString("\n"))
            return
        }

        let source = inlineSource(child)
        var run = AttributedString(source)
        if child.type == "mention", let url = mentionURL(child, baseURL: baseURL) {
            run.link = url
        }
        for mark in child.marks {
            switch mark.type {
            case "strong":
                run.inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(.stronglyEmphasized)
            case "em":
                run.inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(.emphasized)
            case "code", "code_inline":
                run.inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(.code)
            case "link":
                if let url = resolvedSafeURL(mark.stringAttribute("href"), baseURL: baseURL) { run.link = url }
            case "underline":
                run.underlineStyle = .single
            case "strikethrough":
                run.strikethroughStyle = .single
            case "highlight":
                run.backgroundColor = highlightColor(mark.stringAttribute("color"))
            case "comment":
                if mark.attrs["resolved"]?.boolValue != true { run.underlineStyle = .single }
            case "placeholder":
                break
            default:
                break
            }
        }
        output.append(run)
    }
}

func inlineAtomFallback(_ node: ProseMirrorNode) -> String? {
    guard node.text == nil, node.content.isEmpty, node.type != "text" else { return nil }
    switch node.type {
    case "image":
        let alt = node.stringAttribute("alt")?.trimmingCharacters(in: .whitespacesAndNewlines)
        return alt?.isEmpty == false ? "[Image: \(alt!)]" : "[Image]"
    case "mention", "emoji", "math_inline":
        return inlineSource(node)
    default:
        return "[\(node.type)]"
    }
}

func inlineSource(_ node: ProseMirrorNode) -> String {
    if let text = node.text { return text }
    switch node.type {
    case "mention":
        let label = node.stringAttribute("label") ?? "Mention"
        return node.stringAttribute("type") == "user" ? "@\(label)" : label
    case "emoji":
        return emoji(named: node.stringAttribute("data-name") ?? "grey_question")
    case "math_inline":
        return "$\(plainText(node))$"
    default:
        return inlineAtomFallback(node) ?? plainText(node)
    }
}

func resolvedSafeURL(_ source: String?, baseURL: URL?) -> URL? {
    guard let source = source?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty,
          let url = URL(string: source, relativeTo: baseURL)?.absoluteURL,
          let scheme = url.scheme?.lowercased(),
          ["https", "mailto", "tel", "sms"].contains(scheme) else { return nil }
    return url
}

func attachmentDetail(_ node: ProseMirrorNode) -> String? {
    var parts: [String] = []
    if let contentType = node.stringAttribute("contentType"), !contentType.isEmpty { parts.append(contentType) }
    if let bytes = node.intAttribute("size"), bytes > 0 {
        parts.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

func safeAttachmentFilename(_ title: String, fallbackExtension: String? = nil) -> String {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let lastPathComponent = trimmedTitle.isEmpty ? "" : URL(fileURLWithPath: trimmedTitle).lastPathComponent
        .components(separatedBy: .controlCharacters)
        .joined()
        .replacingOccurrences(of: ":", with: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    var filename = lastPathComponent.isEmpty ? "Attachment" : String(lastPathComponent.prefix(100))
    if URL(fileURLWithPath: filename).pathExtension.isEmpty,
       let fallbackExtension,
       !fallbackExtension.isEmpty,
       fallbackExtension.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains) {
        filename += ".\(fallbackExtension.prefix(12))"
    }
    return filename
}

private func mentionURL(_ node: ProseMirrorNode, baseURL: URL?) -> URL? {
    switch node.stringAttribute("type") {
    case "document":
        guard let id = node.stringAttribute("modelId") else { return nil }
        var path = "/doc/\(id)"
        if let anchor = node.stringAttribute("anchorId"), !anchor.isEmpty { path += "#\(anchor)" }
        return resolvedSafeURL(path, baseURL: baseURL)
    case "collection":
        guard let id = node.stringAttribute("modelId") else { return nil }
        return resolvedSafeURL("/collection/\(id)", baseURL: baseURL)
    case "user", "date":
        return nil
    default:
        return resolvedSafeURL(node.stringAttribute("href"), baseURL: baseURL)
    }
}

private func emoji(named name: String) -> String {
    let values = [
        "grey_question": "❔", "thinking_face": "🤔", "thumbsup": "👍", "tada": "🎉",
        "heart": "❤️", "smile": "😄", "warning": "⚠️", "white_check_mark": "✅",
    ]
    return values[name] ?? ":\(name):"
}

private func highlightColor(_ value: String?) -> Color {
    let value = value ?? "#FDEA9B"
    guard value.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil,
          let number = UInt64(value.dropFirst(), radix: 16) else {
        return Color(red: 253 / 255, green: 234 / 255, blue: 155 / 255).opacity(0.4)
    }
    return Color(
        red: Double((number >> 16) & 0xff) / 255,
        green: Double((number >> 8) & 0xff) / 255,
        blue: Double(number & 0xff) / 255
    ).opacity(0.4)
}

private func plainText(_ parent: ProseMirrorNode) -> String {
    if let text = parent.text { return text }
    return parent.content.map(plainText).joined()
}

private func platformImage(data: Data) async throws -> Image? {
    try Task.checkCancellation()
    #if canImport(UIKit)
    guard
        let image = UIImage(data: data),
        let preparedImage = await image.byPreparingForDisplay()
    else {
        return nil
    }
    try Task.checkCancellation()
    return Image(uiImage: preparedImage)
    #elseif canImport(AppKit)
    guard let image = NSImage(data: data) else { return nil }
    return Image(nsImage: image)
    #else
    return nil
    #endif
}
