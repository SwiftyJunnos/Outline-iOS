import Foundation
import Testing
@testable import OutlineCore

@Test
func decodesTolerantDocumentTreeAndUnknownAttributes() throws {
    let data = Data("""
    {
      "id": "document-id",
      "title": "Read me",
      "url": "/doc/document-id",
      "data": {
        "type": "doc",
        "content": [
          {"type": "paragraph", "content": [{"type": "text", "text": "Welcome", "marks": [{"type": "strong"}]}]},
          {"type": "heading", "attrs": {"level": 2, "metadata": {"custom": true}}},
          {"type": "image", "attrs": {"src": "/api/attachments/image", "alt": "Diagram", "layoutClass": "center"}}
        ]
      }
    }
    """.utf8)

    let document = try JSONDecoder().decode(OutlineRichDocument.self, from: data)

    #expect(document.data.content[0].attrs.isEmpty)
    #expect(document.data.content[0].content[0].marks == [ProseMirrorMark(type: "strong")])
    #expect(document.data.content[1].intAttribute("level") == 2)
    #expect(document.data.content[1].attrs["metadata"] == .object(["custom": .bool(true)]))
    #expect(document.data.content[2].stringAttribute("src") == "/api/attachments/image")
}

@Test
func inlineAtomsHaveReadableFallbacks() {
    let image = ProseMirrorNode(type: "image", attrs: ["alt": .string("Architecture")])
    let mention = ProseMirrorNode(
        type: "mention",
        attrs: ["type": .string("user"), "label": .string("Jamie")]
    )
    let emoji = ProseMirrorNode(type: "emoji", attrs: ["data-name": .string("thinking_face")])
    let unknown = ProseMirrorNode(type: "future_node")

    #expect(inlineAtomFallback(image) == "[Image: Architecture]")
    #expect(inlineAtomFallback(mention) == "@Jamie")
    #expect(inlineAtomFallback(emoji) == "🤔")
    #expect(inlineAtomFallback(unknown) == "[future_node]")
}

@Test
func resolvesStableAccessibilityFallbackText() {
    #expect(resolvedAccessibilityText(nil, fallback: "Image") == "Image")
    #expect(resolvedAccessibilityText("   ", fallback: "Image") == "Image")
    #expect(resolvedAccessibilityText("  Diagram  ", fallback: "Image") == "Diagram")
    #expect(resolvedAccessibilityText(nil, fallback: "Embedded content") == "Embedded content")
}

@Test
func decodesOutlineTableContract() throws {
    let data = Data("""
    {
      "type": "table",
      "attrs": {"layout": "full-width"},
      "content": [{
        "type": "tr",
        "content": [
          {"type": "th", "attrs": {"colspan": 2, "alignment": "center"}, "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Heading"}]}]},
          {"type": "td", "attrs": {"rowspan": 2}, "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Value"}]}]}
        ]
      }]
    }
    """.utf8)

    let table = try JSONDecoder().decode(ProseMirrorNode.self, from: data)

    #expect(table.content.first?.type == "tr")
    #expect(table.content.first?.content.first?.intAttribute("colspan") == 2)
    #expect(table.content.first?.content.first?.stringAttribute("alignment") == "center")
    #expect(table.content.first?.content.last?.intAttribute("rowspan") == 2)
}

@Test
func resolvesOnlySafeReaderLinks() {
    let baseURL = URL(string: "https://outline.example/team/")!

    #expect(resolvedSafeURL("/doc/123", baseURL: baseURL)?.absoluteString == "https://outline.example/doc/123")
    #expect(resolvedSafeURL("https://files.example/image.png", baseURL: baseURL)?.host == "files.example")
    #expect(resolvedSafeURL("javascript:alert(1)", baseURL: baseURL) == nil)
    #expect(resolvedSafeURL("http://outline.example/image.png", baseURL: baseURL) == nil)
}

@Test
func matchesOutlineHeadingAnchorsAndDuplicateSuffixes() {
    let heading = ProseMirrorNode(
        type: "heading",
        attrs: ["level": .number(2)],
        content: [ProseMirrorNode(type: "text", text: "Résumé & Next Steps")]
    )
    let nestedHeading = ProseMirrorNode(
        type: "heading",
        content: [ProseMirrorNode(type: "text", text: "Nested Heading")]
    )
    let compatibilityHeadings = [
        "What’s New",
        "“Quoted”",
        "• Notes…",
        "Примечания",
        "구현 환경",
    ].map {
        ProseMirrorNode(
            type: "heading",
            content: [ProseMirrorNode(type: "text", text: $0)]
        )
    }
    let document = ProseMirrorNode(type: "doc", content: [
        heading,
        heading,
        ProseMirrorNode(
            type: "heading",
            content: [ProseMirrorNode(type: "text", text: "Hello_world")]
        ),
        ProseMirrorNode(type: "container_notice", content: [nestedHeading]),
    ] + compatibilityHeadings)

    let anchors = outlineHeadingAnchors(in: document)

    #expect(anchors[[0]] == "h-resume-and-next-steps")
    #expect(anchors[[1]] == "h-resume-and-next-steps-1")
    #expect(anchors[[2]] == "h-helloworld")
    #expect(anchors[[3, 0]] == "h-nested-heading")
    #expect(anchors[[4]] == "h-whats-new")
    #expect(anchors[[5]] == "h-quoted")
    #expect(anchors[[6]] == "h-notes")
    #expect(anchors[[7]] == "h-primechaniya")
    #expect(anchors[[8]] == "h-구현-환경")
}

@Test
func rendersRichInlineMarksAndMetadata() {
    let node = ProseMirrorNode(
        type: "paragraph",
        content: [
            ProseMirrorNode(
                type: "text",
                text: "Review",
                marks: [
                    ProseMirrorMark(type: "highlight", attrs: ["color": .string("#FDEA9B")]),
                    ProseMirrorMark(type: "comment", attrs: ["resolved": .bool(false)]),
                    ProseMirrorMark(type: "placeholder"),
                    ProseMirrorMark(type: "code_inline"),
                ]
            ),
            ProseMirrorNode(type: "math_inline", content: [ProseMirrorNode(type: "text", text: "x^2")]),
        ]
    )
    let attachment = ProseMirrorNode(
        type: "attachment",
        attrs: [
            "contentType": .string("application/pdf"),
            "size": .number(1_024),
        ]
    )

    let rendered = inlineText(node)
    #expect(String(rendered.characters) == "Review$x^2$")
    #expect(rendered.runs.first?.backgroundColor != nil)
    #expect(rendered.runs.first?.underlineStyle == .single)
    #expect(rendered.runs.first?.inlinePresentationIntent?.contains(.code) == true)
    #expect(attachmentDetail(attachment) == "application/pdf · 1 KB")
}

@Test
func identifiesMermaidCodeFence() {
    let node = ProseMirrorNode(
        type: "code_fence",
        attrs: ["language": .string("mermaid")],
        content: [ProseMirrorNode(type: "text", text: "flowchart LR\nA --> B")]
    )

    #expect(isMermaidCodeBlock(node))
    #expect(isMermaidCodeBlock(ProseMirrorNode(
        type: "code_block",
        attrs: ["language": .string("Mermaid")]
    )))
    #expect(!isMermaidCodeBlock(ProseMirrorNode(
        type: "code_fence",
        attrs: ["language": .string("swift")]
    )))
}

@Test
func highlightsKnownCodeLanguagesAndFallsBackForUnknownOnes() {
    let source = #"let answer = 42 // result"#
    let highlighted = highlightedCode(source, language: "swift")
    let plain = highlightedCode(source, language: "plaintext")

    #expect(normalizedCodeLanguage("TSX") == "typescript")
    #expect(highlighted.runs.contains { $0.foregroundColor != nil })
    #expect(!plain.runs.contains { $0.foregroundColor != nil })
}

@Test
func sanitizesDownloadedAttachmentFilenames() {
    #expect(safeAttachmentFilename("../../report", fallbackExtension: "pdf") == "report.pdf")
    #expect(safeAttachmentFilename("video.mp4", fallbackExtension: "mov") == "video.mp4")
    #expect(safeAttachmentFilename("", fallbackExtension: "bin") == "Attachment.bin")
}

@Test
func decodesProductionShapedFixtureCorpus() throws {
    // Shapes adapted from Outline's NotionConverter snapshot:
    // plugins/notion/server/utils/__snapshots__/NotionConverter.test.ts.snap
    let url = try #require(Bundle.module.url(
        forResource: "notion-converter-page",
        withExtension: "json"
    ))
    let document = try JSONDecoder().decode(
        OutlineRichDocument.self,
        from: Data(contentsOf: url)
    )
    let types = Set(allNodeTypes(in: document.data))

    #expect(document.id == "fixture-document")
    #expect([
        "attachment", "bullet_list", "checkbox_list", "code_fence",
        "container_notice", "container_toggle", "embed", "image",
        "math_block", "table", "video",
    ].allSatisfy(types.contains))
}

@Test
func preservesUnknownNodeFixtureWithoutDroppingFollowingContent() throws {
    let url = try #require(Bundle.module.url(
        forResource: "unknown-node-document",
        withExtension: "json"
    ))
    let document = try JSONDecoder().decode(
        OutlineRichDocument.self,
        from: Data(contentsOf: url)
    )

    let unknown = try #require(document.data.content.first)
    #expect(unknown.type == "future_block")
    #expect(unknown.attrs["enabled"] == .bool(true))
    #expect(unknown.attrs["metadata"] == .object(["version": .number(2)]))
    #expect(unknown.attrs["values"] == .array([.string("one"), .number(2), .null]))
    #expect(unknown.content.first?.text == "Forward-compatible content")
    #expect(document.data.content.last?.content.first?.text == "Following block")
}

@Test
func decodesLongMixedDocumentWithoutLosingBlocks() throws {
    let blocks: [[String: Any]] = (0..<1_500).map { index in
        if index.isMultiple(of: 3) {
            return [
                "type": "code_fence",
                "attrs": ["language": "swift"],
                "content": [["type": "text", "text": "let value = \(index)"]],
            ]
        }
        return [
            "type": index.isMultiple(of: 2) ? "heading" : "paragraph",
            "attrs": ["level": 2],
            "content": [["type": "text", "text": "Block \(index)"]],
        ]
    }
    let data = try JSONSerialization.data(withJSONObject: [
        "id": "long-document",
        "title": "Long document",
        "url": "/doc/long-document",
        "data": ["type": "doc", "content": blocks],
    ])

    let document = try JSONDecoder().decode(OutlineRichDocument.self, from: data)

    #expect(document.data.content.count == 1_500)
    #expect(document.data.content[1_499].content.first?.text == "Block 1499")
}

private func allNodeTypes(in node: ProseMirrorNode) -> [String] {
    [node.type] + node.content.flatMap(allNodeTypes)
}
