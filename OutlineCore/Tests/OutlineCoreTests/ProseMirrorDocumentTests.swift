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
func inlineImageHasVisibleFallback() {
    let image = ProseMirrorNode(type: "image", attrs: ["alt": .string("Architecture")])
    let unknown = ProseMirrorNode(type: "mention")

    #expect(inlineAtomFallback(image) == "[Image: Architecture]")
    #expect(inlineAtomFallback(unknown) == "[mention]")
}
