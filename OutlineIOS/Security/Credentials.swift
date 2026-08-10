import Foundation

struct Credentials: Codable, Sendable {
    let serverURL: URL
    let token: String
}
