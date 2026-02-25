import Foundation

public enum JSONValue: Sendable, Equatable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }
        if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
            return
        }
        if let intValue = try? container.decode(Int.self) {
            self = .number(Double(intValue))
            return
        }
        if let doubleValue = try? container.decode(Double.self) {
            self = .number(doubleValue)
            return
        }
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }
        if let arrayValue = try? container.decode([JSONValue].self) {
            self = .array(arrayValue)
            return
        }
        if let objectValue = try? container.decode([String: JSONValue].self) {
            self = .object(objectValue)
            return
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            if value.rounded() == value {
                try container.encode(Int(value))
            } else {
                try container.encode(value)
            }
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public init(foundationObject: Any) throws {
        switch foundationObject {
        case let value as String:
            self = .string(value)
        case let value as Bool:
            self = .bool(value)
        case let value as Int:
            self = .number(Double(value))
        case let value as Double:
            self = .number(value)
        case let value as NSNumber:
            self = .number(value.doubleValue)
        case let value as [Any]:
            self = .array(try value.map { try JSONValue(foundationObject: $0) })
        case let value as [String: Any]:
            var object: [String: JSONValue] = [:]
            for (key, nested) in value {
                object[key] = try JSONValue(foundationObject: nested)
            }
            self = .object(object)
        case _ as NSNull:
            self = .null
        default:
            throw AIServiceError.parsingError("Unsupported JSON foundation object.")
        }
    }

    public var foundationObject: Any {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .object(let value):
            return value.mapValues { $0.foundationObject }
        case .array(let value):
            return value.map { $0.foundationObject }
        case .null:
            return NSNull()
        }
    }

    public var displayText: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return "null"
        case .array, .object:
            guard JSONSerialization.isValidJSONObject(foundationObject),
                  let data = try? JSONSerialization.data(
                    withJSONObject: foundationObject,
                    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                  ),
                  let text = String(data: data, encoding: .utf8)
            else {
                return ""
            }
            return text
        }
    }
}
