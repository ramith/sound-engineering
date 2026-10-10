// EQOutcome — what one EQ verb asks of the app (Sprint EQ; review fix round). `EQSession` decides; the
// view model only carries the outcome out: the one send to the engine, the two writes, the UX log and
// the output toast. So every decision is the kit's, and tested there.

public struct EQOutcome: Equatable, Sendable {
    /// The side effects to carry out.
    public struct Effects: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// Send what plays to the engine: the points, and whether the EQ plays (`EQSession.plays`).
        public static let send = Effects(rawValue: 1 << 0)
        /// Write the slots (`eqStateV2`).
        public static let saveSlots = Effects(rawValue: 1 << 1)
        /// Write My Presets (`eqCustomPresetsV1`).
        public static let saveMyPresets = Effects(rawValue: 1 << 2)
    }

    public private(set) var effects: Effects

    /// Lines for the UX log, in order.
    public private(set) var log: [String]

    /// The output toast to raise ("AirPods Pro · Vocal"), when the sound changed with the output.
    public private(set) var toast: String?

    /// Nothing to do: the verb didn't apply (no stroke to end, a preset that is gone, a refused name).
    public static let none = EQOutcome([])

    init(_ effects: Effects, log: String? = nil, toast: String? = nil) {
        self.effects = effects
        self.log = log.map { [$0] } ?? []
        self.toast = toast
    }

    /// Whether the verb did anything.
    public var isNone: Bool {
        self == .none
    }

    /// This outcome followed by `next`: both sets of effects, the log lines in order.
    func then(_ next: EQOutcome) -> EQOutcome {
        var merged = self
        merged.effects.formUnion(next.effects)
        merged.log += next.log
        merged.toast = next.toast ?? toast
        return merged
    }
}
