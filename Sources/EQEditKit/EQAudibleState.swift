// EQAudibleState — what the listener hears from the EQ right now (Sprint EQ, EQ3; ui-plan §4). One
// rule decides the graph's look, the strip's copy and whether Compare can be held, so the three can
// never disagree about whether the curve on screen is playing.

public enum EQAudibleState: Equatable, Sendable {
    /// The EQ plays the curve on screen.
    case playing
    /// The EQ is switched off: a true bypass, at matched loudness (decision 26).
    case off
    /// Compare is held: the song plays without the EQ until it is released (decision 28).
    case comparing
    /// Pure Mode's bit-perfect path is playing: no DSP runs at all, the EQ included.
    case pureMode
    /// The audio engine isn't running yet: nothing plays, and the EQ plays as set once it starts.
    case engineNotReady

    /// The state for these facts. The first that applies wins: Off (the user's own switch — an EQ that
    /// is off draws no response whatever else is true), then no engine, then Pure Mode (no EQ can play
    /// on either), then a held Compare.
    public init(isOn: Bool, isComparing: Bool, pureModeEngaged: Bool, engineReady: Bool) {
        self = if !isOn {
            .off
        } else if !engineReady {
            .engineNotReady
        } else if pureModeEngaged {
            .pureMode
        } else if isComparing {
            .comparing
        } else {
            .playing
        }
    }

    /// Whether the solid curve draws the EQ's response. Off, Pure Mode and a held Compare draw what
    /// plays instead: a flat 0 dB. A stopped engine still draws the EQ as it will play once it runs.
    public var drawsResponse: Bool {
        self == .playing || self == .engineNotReady
    }

    /// Whether the graph shows the readouts of an edit in progress — the keyboard cursor's, a Tone
    /// slider's, with its shaded region: while the EQ plays, and where it is on but can't be heard yet
    /// (Pure Mode, no engine), since editing goes on there. Off and a held Compare say what plays
    /// instead; any edit ends both.
    public var showsEditReadouts: Bool {
        self == .playing || self == .pureMode || self == .engineNotReady
    }

    /// Whether Compare can be held (or is): only while the EQ really plays — there is nothing to
    /// compare while it is off, in Pure Mode or with no engine.
    public var canCompare: Bool {
        self == .playing || self == .comparing
    }
}
