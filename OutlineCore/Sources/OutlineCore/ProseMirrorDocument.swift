import Foundation

public struct OutlineRichDocument: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let url: String
    public let data: ProseMirrorNode

    public init(id: String, title: String, url: String, data: ProseMirrorNode) {
        self.id = id
        self.title = title
        self.url = url
        self.data = data
    }
}

public struct ProseMirrorNode: Codable, Equatable, Sendable {
    public let type: String
    public let attrs: [String: ProseMirrorValue]
    public let content: [ProseMirrorNode]
    public let text: String?
    public let marks: [ProseMirrorMark]

    public init(
        type: String,
        attrs: [String: ProseMirrorValue] = [:],
        content: [ProseMirrorNode] = [],
        text: String? = nil,
        marks: [ProseMirrorMark] = []
    ) {
        self.type = type
        self.attrs = attrs
        self.content = content
        self.text = text
        self.marks = marks
    }

    private enum CodingKeys: String, CodingKey {
        case type, attrs, content, text, marks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        attrs = try container.decodeIfPresent([String: ProseMirrorValue].self, forKey: .attrs) ?? [:]
        content = try container.decodeIfPresent([ProseMirrorNode].self, forKey: .content) ?? []
        text = try container.decodeIfPresent(String.self, forKey: .text)
        marks = try container.decodeIfPresent([ProseMirrorMark].self, forKey: .marks) ?? []
    }

    public func stringAttribute(_ key: String) -> String? {
        attrs[key]?.stringValue
    }

    public func intAttribute(_ key: String) -> Int? {
        attrs[key]?.intValue
    }

    public func boolAttribute(_ key: String) -> Bool? {
        attrs[key]?.boolValue
    }
}

public struct ProseMirrorMark: Codable, Equatable, Sendable {
    public let type: String
    public let attrs: [String: ProseMirrorValue]

    public init(type: String, attrs: [String: ProseMirrorValue] = [:]) {
        self.type = type
        self.attrs = attrs
    }

    private enum CodingKeys: String, CodingKey {
        case type, attrs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        attrs = try container.decodeIfPresent([String: ProseMirrorValue].self, forKey: .attrs) ?? [:]
    }

    public func stringAttribute(_ key: String) -> String? {
        attrs[key]?.stringValue
    }
}

public enum ProseMirrorValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: ProseMirrorValue])
    case array([ProseMirrorValue])
    case null

    public var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    public var intValue: Int? {
        guard case let .number(value) = self else { return nil }
        return Int(exactly: value)
    }

    public var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    private struct CodingKey: Swift.CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKey.self) {
            var object: [String: ProseMirrorValue] = [:]
            for key in container.allKeys {
                object[key.stringValue] = try container.decode(ProseMirrorValue.self, forKey: key)
            }
            self = .object(object)
            return
        }

        if var container = try? decoder.unkeyedContainer() {
            var array: [ProseMirrorValue] = []
            while !container.isAtEnd {
                array.append(try container.decode(ProseMirrorValue.self))
            }
            self = .array(array)
            return
        }

        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported ProseMirror JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .object(object):
            var container = encoder.container(keyedBy: CodingKey.self)
            for (key, value) in object {
                guard let codingKey = CodingKey(stringValue: key) else { continue }
                try container.encode(value, forKey: codingKey)
            }
        case let .array(array):
            var container = encoder.unkeyedContainer()
            for value in array {
                try container.encode(value)
            }
        case let .string(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .number(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .bool(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
}
