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

    /// Pins this build can't read (a damaged write, or a later build's reshaped key), keyed by UID as
    /// stored. They resolve to no output, but they are written back unchanged, so no save makes their
    /// loss permanent (break-it BRK-01); one is replaced only when its UID is pinned again.
    private(set) var unreadablePins: [String: EQOpaqueJSON]

    /// The fingerprint of the v1 EQ (`eqLiveStateV1`) this store last took in (`EQMigration`); `nil`
    /// for a store written before that rule.
    var v1Fingerprint: String?

    /// A store whose every output plays `shared` (nothing pinned).
    public init(shared: EQState) {
        self.init(shared: shared, pinned: [:])
    }

    init(shared: EQState, pinned: [String: PinnedSlot], unreadablePins: [String: EQOpaqueJSON] = [:],
         v1Fingerprint: String? = nil) {
        self.shared = shared
        self.pinned = pinned
        self.unreadablePins = unreadablePins
        self.v1Fingerprint = v1Fingerprint
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

    /// Whether the output moving from `old` to `new` moves the EQ to another slot. A move between two
    /// outputs that play the same slot (two unpinned outputs both play shared) changes nothing that
    /// is edited, so a drag carries on across it (break-it D1).
    public func isSlotChange(from old: EQOutputKey?, to new: EQOutputKey?) -> Bool {
        slotID(for: old) != slotID(for: new)
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

    // MARK: - Pins (EQ4; decision 28: a pinned output remembers exactly what was last heard on it)

    /// How `output` stands with the pins (`nil`: no output, or one that can't be pinned).
    public func pin(for output: EQOutputKey?) -> EQOutputPin? {
        guard let output, output.isPinnable else { return nil }
        guard let pin = slotID(for: output).flatMap({ pinned[$0]?.key }) else { return .unpinned(output) }
        return pin.uid == output.uid ? .pinned(output) : .sharedWith(pin, on: output)
    }

    /// Pins `output`: it gets a slot of its own holding exactly what it plays now — edits and Tone
    /// included — so nothing audible changes, and from then on its edits are its own. One pin per model
    /// (amendment 13, as the pin and its tooltip say): an output that already plays a pin — its own, or
    /// the one it shares with its model — is left as it is, and so is one that can't be pinned
    /// (`EQOutputKey.isPinnable`).
    public mutating func pin(_ output: EQOutputKey) {
        guard output.isPinnable, slotID(for: output) == nil else { return }
        let playing = shared
        pinned[output.uid] = PinnedSlot(key: output, state: playing)
        unreadablePins[output.uid] = nil
    }

    /// Unpins the pin `output` plays — its own, or the one it shares with its model — and that pin's
    /// state becomes the shared slot's, so nothing audible changes (ui-plan §3.3). Every output that
    /// played the pin plays shared from then on. Nothing to do when `output` plays shared already.
    public mutating func unpin(_ output: EQOutputKey?) {
        guard let id = slotID(for: output), let slot = pinned.removeValue(forKey: id) else { return }
        shared = slot.state
    }

    // MARK: - Save (EQ4; break-it C1)

    /// What Save takes when its sheet opens: what plays on `output`, and the slot it plays in.
    public func saveSource(for output: EQOutputKey?) -> EQSaveSource {
        let id = slotID(for: output)
        return EQSaveSource(state: self[slot: id], slotID: id)
    }

    /// Saves `source` as the My Preset `name`: its slot — the one it came from, whatever plays now —
    /// plays that preset unedited, the Tone baked in. Returns the saved state.
    mutating func save(_ source: EQSaveSource, as name: String) -> EQState {
        let saved = source.state.saved(as: name)
        self[slot: source.slotID] = saved
        return saved
    }
}

// MARK: - Codable ({"version": 2, "shared": state, "pinned": {uid: {"key", "state"}}, "v1Fingerprint"})

extension EQStore: Codable {
    /// The schema this build reads and writes.
    private static let version = 2

    private enum CodingKeys: String, CodingKey {
        case version, shared, pinned, v1Fingerprint
    }

    /// Any other version throws. Below that, nothing damaged costs anything else: a state that can't
    /// be read plays Flat (`EQState` keeps what it can of it), and a pin that can't be read is kept
    /// aside unchanged while the others play on. Only a `pinned` value that isn't a map loses the pins.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == Self.version else {
            throw DecodingError.dataCorruptedError(
                forKey: .version, in: container,
                debugDescription: "EQStore v\(version); this build reads v\(Self.version)"
            )
        }
        let pins = (try? container.decode([String: StoredPin].self, forKey: .pinned)) ?? [:]
        self.init(
            shared: (try? container.decode(EQState.self, forKey: .shared)) ?? .flat,
            pinned: pins.compactMapValues(\.readable),
            unreadablePins: pins.compactMapValues(\.unreadable),
            v1Fingerprint: try? container.decodeIfPresent(String.self, forKey: .v1Fingerprint)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.version, forKey: .version)
        try container.encode(shared, forKey: .shared)
        // A readable pin wins over an unreadable entry under the same UID: that output was pinned again.
        let pins = unreadablePins.mapValues(StoredPin.unreadable)
            .merging(pinned.mapValues(StoredPin.readable)) { _, readable in readable }
        try container.encode(pins, forKey: .pinned)
        try container.encodeIfPresent(v1Fingerprint, forKey: .v1Fingerprint)
    }
}

/// One stored pin: read when this build can, else kept exactly as it was stored.
private enum StoredPin: Codable {
    case readable(EQStore.PinnedSlot)
    case unreadable(EQOpaqueJSON)

    var readable: EQStore.PinnedSlot? {
        guard case let .readable(slot) = self else { return nil }
        return slot
    }

    var unreadable: EQOpaqueJSON? {
        guard case let .unreadable(json) = self else { return nil }
        return json
    }

    init(from decoder: any Decoder) throws {
        if let slot = try? EQStore.PinnedSlot(from: decoder) {
            self = .readable(slot)
        } else {
            self = try .unreadable(EQOpaqueJSON(from: decoder))
        }
    }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case let .readable(slot): try slot.encode(to: encoder)
        case let .unreadable(json): try json.encode(to: encoder)
        }
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
