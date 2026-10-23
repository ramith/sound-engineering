import Foundation

// MARK: - How an engine runs a start, a stop or a seek: the C-15 design, and what it replaced

/// How the engine runs a transport command (start, stop, seek) that reaches its queue.
enum CommandSemantics: Sendable, CustomStringConvertible {
    /// 532ab79: every command runs, whatever its epoch — a stop overtaken by a later start on its way to
    /// the queue still stops it.
    case executesEvery
    /// The design (council C-15): a command older than one the engine has already begun was overtaken
    /// on its way, and is dropped — no effect at all.
    case dropsOvertaken

    var description: String {
        switch self {
        case .executesEvery: "532ab79 (executes every command)"
        case .dropsOvertaken: "design"
        }
    }
}

// MARK: - How an engine applies a "play next" request: the D41 design, and what it replaced

/// How the engine applies a "play next" request.
enum ArmSemantics: Sendable, CustomStringConvertible {
    /// 672fc0a: no gate. Pure arms when the open lands and refuses while a pick is armed (also after
    /// the end); Enhanced replaces the slot when the request lands.
    case refuse
    /// The P3a remedy: no gate; when an open lands, clear then arm — the last open to land wins.
    case clearThenArm
    /// The gate, but the old pick stays armed until the new pick's open lands (no retract at
    /// admission).
    case gatedReplaceAfterOpen
    /// The design: the gate, the old pick off at admission, the arm only while current; `endFinal`
    /// is "the end is final", `monotonicSessions` that a start or stop older than the engine's
    /// playback changes nothing (AMEND-1; `false` is the design as first written).
    case gatedRetractFirst(endFinal: Bool, monotonicSessions: Bool = true)

    static let design = ArmSemantics.gatedRetractFirst(endFinal: true)

    var gated: Bool {
        switch self {
        case .refuse, .clearThenArm: false
        case .gatedReplaceAfterOpen, .gatedRetractFirst: true
        }
    }

    var retractsAtAdmission: Bool {
        if case .gatedRetractFirst = self {
            return true
        }
        return false
    }

    var endFinal: Bool {
        switch self {
        case .refuse, .clearThenArm: false
        case .gatedReplaceAfterOpen: true
        case let .gatedRetractFirst(endFinal, _): endFinal
        }
    }

    var monotonicSessions: Bool {
        if case let .gatedRetractFirst(_, monotonic) = self {
            return monotonic
        }
        return true
    }

    var description: String {
        switch self {
        case .refuse: "672fc0a (refuse)"
        case .clearThenArm: "clearThenArm"
        case .gatedReplaceAfterOpen: "gatedReplaceAfterOpen"
        case let .gatedRetractFirst(endFinal, monotonic):
            endFinal && monotonic ? "design"
                : "gatedRetractFirst(endFinal: \(endFinal), monotonicSessions: \(monotonic))"
        }
    }
}
