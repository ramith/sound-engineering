// EQStore — every EQ the app remembers, persisted whole as `eqStateV2` (Sprint EQ, EQ3a; review
// F5/F8 + §4): per-output memory as SLOTS. Every unpinned output plays `shared`; a pinned output
// plays its own slot, keyed by the device's persistent UID. Edits write to the current output's
// slot, so switching outputs never loses an edit — the store IS the per-output memory, with no
// separate recall map to drift out of step with it.
//
// One aggregate, one key, written atomically: the version lives in the blob as well as in the key
// name, so a later schema decodes this one inside the kit.

public struct EQStore: Equatable, Sendable {
    /// One pinned output's slot: the output as it was pinned (its model UID is the fallback match,
    /// its name is for display) and the state it plays.
    struct PinnedSlot: Equatable, Sendable {
        let key: EQOutputKey
        var state: EQState
    }

    /// What every unpinned output plays.
    private(set) var shared: EQState

    /// The pinned outputs' slots, keyed by device UID.
    private(set) var pinned: [String: PinnedSlot]

    /// A store whose every output plays `shared` (nothing pinned).
    public init(shared: EQState) {
        self.init(shared: shared, pinned: [:])
    }

    init(shared: EQState, pinned: [String: PinnedSlot]) {
        self.shared = shared
        self.pinned = pinned
    }

    /// The slot `output` plays: its own pin by exact UID; else the one pin of the same model (a
    /// second unit of the pinned model) when exactly one pin has that model UID; else `nil`, the
    /// shared slot. An output that can't be pinned (`EQOutputKey.isPinnable`) always plays shared.
    public func slotID(for output: EQOutputKey?) -> String? {
        guard let output, output.isPinnable else { return nil }
        if pinned[output.uid] != nil {
            return output.uid
        }
        guard let modelUID = output.modelUID else { return nil }
        let sameModel = pinned.filter { $0.value.key.modelUID == modelUID }
        return sameModel.count == 1 ? sameModel.first?.key : nil
    }

    /// The state in slot `id` (`nil` or an unknown id: the shared slot), read or written.
    public subscript(slot id: String?) -> EQState {
        get { id.flatMap { pinned[$0]?.state } ?? shared }
        set {
            if let id, pinned[id] != nil {
                pinned[id]?.state = newValue
            } else {
                shared = newValue
            }
        }
    }

    /// Re-points every slot that plays a My Preset: `newName(name)` is the preset's name now, or
    /// `nil` once it is gone, and that slot keeps its curve as an edited Flat. One rule for a
    /// rename, a delete, and a reference left dangling while the store was on disk.
    public mutating func repointMyPresets(_ newName: (String) -> String?) {
        shared.repointMyPreset(newName)
        for id in pinned.keys {
            pinned[id]?.state.repointMyPreset(newName)
        }
    }
}

// MARK: - Codable ({"version": 2, "shared": state, "pinned": {uid: {"key", "state"}}})

extension EQStore: Codable {
    /// The schema this build reads and writes.
    private static let version = 2

    private enum CodingKeys: String, CodingKey {
        case version, shared, pinned
    }

    /// Any other version throws. Below that, a state that can't be read plays Flat rather than
    /// losing the rest (the shared slot, or that one pin); only unreadable pin keys lose the pins.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == Self.version else {
            throw DecodingError.dataCorruptedError(
                forKey: .version, in: container,
                debugDescription: "EQStore v\(version); this build reads v\(Self.version)"
            )
        }
        self.init(
            shared: (try? container.decode(EQState.self, forKey: .shared)) ?? .flat,
            pinned: (try? container.decode([String: PinnedSlot].self, forKey: .pinned)) ?? [:]
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.version, forKey: .version)
        try container.encode(shared, forKey: .shared)
        try container.encode(pinned, forKey: .pinned)
    }
}

extension EQStore.PinnedSlot: Codable {
    private enum CodingKeys: String, CodingKey {
        case key, state
    }

    /// The key must read; a state that doesn't plays Flat on that output, and the pin is kept.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(key: container.decode(EQOutputKey.self, forKey: .key),
                      state: (try? container.decode(EQState.self, forKey: .state)) ?? .flat)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(state, forKey: .state)
    }
}
