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
    #expect(attachmentDetail(attachment) == "application/pdf · 1 KB")
}
