import OutlineCore

struct OutlineComment: Decodable, Identifiable, Sendable, Equatable {
    let id: String
    let data: ProseMirrorNode
    let createdBy: Author
    let createdAt: String
    let resolvedAt: String?

    struct Author: Decodable, Sendable, Equatable {
        let name: String
    }
}
