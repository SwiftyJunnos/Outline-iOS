import Foundation

struct OutlineDocument: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let text: String
    let url: String
}
