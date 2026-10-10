// EQOutputPin — how the current output stands with the pins (Sprint EQ, EQ4; decision 28): the
// "Used on <output>" pin in the graph card's header and the presets' menu read it.

public enum EQOutputPin: Equatable, Sendable {
    /// The output plays the shared slot, like every other unpinned output.
    case unpinned(EQOutputKey)

    /// The output has its own pin: it remembers exactly what was last heard on it.
    case pinned(EQOutputKey)

    /// The output plays `pin`, the one pin of its model (the model-UID fallback: a second pair of
    /// pinned AirPods, a DAC moved to another port). Its edits land in that pin too (amendment 13).
    case sharedWith(EQOutputKey, on: EQOutputKey)

    /// The output this is about: the one playing now.
    public var output: EQOutputKey {
        switch self {
        case let .unpinned(output), let .pinned(output), let .sharedWith(_, on: output): output
        }
    }

    /// Whether the output plays a pin (its own, or its model's).
    public var isPinned: Bool {
        if case .unpinned = self {
            return false
        }
        return true
    }
}
