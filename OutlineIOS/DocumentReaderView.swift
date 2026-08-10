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

                ProseMirrorBlock(node: document.data)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .textSelection(.enabled)
    }
}

private struct ProseMirrorBlock: View {
    let node: ProseMirrorNode

    var body: some View {
        switch node.type {
        case "doc":
            blocks(node.content)
        case "paragraph":
            Text(inlineText(node))
                .font(.body)
                .lineSpacing(6)
        case "heading":
            Text(inlineText(node))
                .font(headingFont)
                .accessibilityAddTraits(.isHeader)
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
                    Rectangle()
                        .fill(.secondary)
                        .frame(width: 3)
                }
        case "code_block", "code_fence":
            ScrollView(.horizontal) {
                Text(plainText(node))
                    .font(.body.monospaced())
                    .padding(12)
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        case "horizontal_rule":
            Divider()
        case "hard_break":
            Text("\n")
        default:
            Label("Unsupported \(node.type) block — open in Outline to view", systemImage: "doc.badge.ellipsis")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func blocks(_ nodes: [ProseMirrorNode]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(nodes.enumerated()), id: \.offset) { _, child in
                ProseMirrorBlock(node: child)
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
                    ProseMirrorBlock(node: item)
                }
            }
        }
    }

    private func marker(for item: ProseMirrorNode, index: Int, ordered: Bool) -> String {
        if node.type == "checkbox_list" {
            return item.boolAttribute("checked") == true ? "☑" : "☐"
        }
        if ordered {
            return "\((node.intAttribute("order") ?? 1) + index)."
        }
        return "•"
    }

    private var headingFont: Font {
        switch node.intAttribute("level") ?? 1 {
        case 1: .title.bold()
        case 2: .title2.bold()
        default: .title3.bold()
        }
    }

    private func inlineText(_ parent: ProseMirrorNode) -> AttributedString {
        parent.content.reduce(into: AttributedString()) { output, child in
            if child.type == "hard_break" {
                output.append(AttributedString("\n"))
                return
            }

            var run = AttributedString(child.text ?? plainText(child))
            for mark in child.marks {
                switch mark.type {
                case "strong":
                    run.inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(.stronglyEmphasized)
                case "em":
                    run.inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(.emphasized)
                case "code":
                    run.inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(.code)
                case "link":
                    if let href = mark.stringAttribute("href"), let url = URL(string: href) {
                        run.link = url
                    }
                case "underline":
                    run.underlineStyle = .single
                case "strikethrough":
                    run.strikethroughStyle = .single
                default:
                    break
                }
            }
            output.append(run)
        }
    }

    private func plainText(_ parent: ProseMirrorNode) -> String {
        if let text = parent.text {
            return text
        }
        return parent.content.map(plainText).joined()
    }
}
