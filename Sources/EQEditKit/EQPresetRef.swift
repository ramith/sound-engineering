// EQPresetRef — which preset a slot plays (Sprint EQ, EQ3a; the contract's name): one of the
// shipped built-ins by its stable id, or one of the user's own (My Presets) by name.
//
// Stored as one key naming the kind — {"builtIn":"Warm"} or {"mine":"Late Night"} — so the
// persisted state reads plainly and a built-in keeps the id it has always had on disk.

public enum EQPresetRef: Hashable, Sendable {
    case builtIn(EQBuiltInPreset)
    case mine(String)

    /// The preset's name as the user sees it.
    public var displayName: String {
        switch self {
        case let .builtIn(preset): preset.displayName
        case let .mine(name): name
        }
    }

    /// The points this preset plays today; `nil` for a My Preset that no longer exists.
    /// `myPresets` is the user's saved presets, name → points (`eqCustomPresetsV1`).
    func points(myPresets: [String: [Float]]) -> [Float]? {
        switch self {
        case let .builtIn(preset): preset.points
        case let .mine(name): myPresets[name]
        }
    }
}

// MARK: - Codable ({"builtIn": id} or {"mine": name})

extension EQPresetRef: Codable {
    private enum CodingKeys: String, CodingKey {
        case builtIn, mine
    }

    /// Decodes exactly one kind. An id this build doesn't know (a built-in from a newer build)
    /// throws, and the state holding it falls back to Flat (`EQState`).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let name = try container.decodeIfPresent(String.self, forKey: .mine) {
            self = .mine(name)
        } else {
            self = try .builtIn(container.decode(EQBuiltInPreset.self, forKey: .builtIn))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .builtIn(preset): try container.encode(preset, forKey: .builtIn)
        case let .mine(name): try container.encode(name, forKey: .mine)
        }
    }
}
