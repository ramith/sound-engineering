// EQOpaqueJSON — a stored JSON value kept exactly as it was read (Sprint EQ, EQ3a fix; break-it
// BRK-01). For stored data this build can't interpret but must not lose — a pin with a damaged key,
// or one a later build wrote in a shape this one doesn't know — so it is written back unchanged and a
// build that can read it finds it again.

enum EQOpaqueJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([EQOpaqueJSON])
    case object([String: EQOpaqueJSON])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([EQOpaqueJSON].self) {
            self = .array(value)
        } else {
            self = try .object(container.decode([String: EQOpaqueJSON].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}
