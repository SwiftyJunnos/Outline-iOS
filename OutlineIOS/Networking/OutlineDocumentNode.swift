import Foundation

struct OutlineDocumentNode: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let url: String
    let children: [OutlineDocumentNode]

    var outlineChildren: [OutlineDocumentNode]? {
        children.isEmpty ? nil : children
    }
}
