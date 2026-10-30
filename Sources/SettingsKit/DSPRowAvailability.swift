// DSPRowAvailability — the shared "Off in bit-perfect mode" row state (R1.1-B, US-R1F-20 items 1–2), and the
// registry of the rows that wear it.
//
// Pure sends the file to the device untouched, so no control that changes the sound in the app's engine can act
// while Pure plays. Each such control's row then reads one state, in one set of words, with one action — Leave
// Pure — instead of looking broken. The state follows the PATH ACTUALLY PLAYING (`SignalPathInfo.path`), not the
// Pure switch: Pure asked for while Enhanced plays (Bluetooth, a channel mismatch) leaves every row live. And
// Leave Pure takes effect the way the Pure switch always does — the next time a song is started — so until then
// the row stays inert and says when Enhanced comes back.
//
// THE REGISTRY is `DSPRow.allCases`. A row the app shows gets its state only through it (the app's one row gate,
// `UI/Controls/BitPerfectRowState.swift`), the tests walk every case, and a registered row the UI never gates
// fails the app's registry test.

/// A control that changes the sound in the app's engine — which Pure bypasses.
public enum DSPRow: String, CaseIterable, Sendable {
    /// The EQ's On / Off switch.
    case equalizer
    /// The Tone card's five sliders.
    case tone
    /// Crossfeed's switch (Headphones).
    case crossfeed
    /// Leveling (Settings).
    case leveling

    /// What the row reads while Pure plays: the shared words, or the row's own where it has them (Leveling, whose
    /// "off" is the point — founder, 2026-10-25).
    public var bitPerfectText: String {
        switch self {
        case .leveling: "Leveling off (bit-perfect)"
        case .equalizer, .tone, .crossfeed: DSPRowAvailability.stateText
        }
    }
}

/// Whether a DSP row works now.
public enum DSPRowAvailability: Equatable, Sendable {
    /// The row works: Enhanced plays (or nothing does yet).
    case live
    /// Pure plays, so the row is inert and says so. `leaving`: the listener has switched Pure off, which takes
    /// effect at the next start — the row says when Enhanced comes back instead of offering Leave Pure again.
    case notInBitPerfectMode(leaving: Bool)

    /// The state of every DSP row: inert exactly while the path in use is Pure.
    /// - Parameters:
    ///   - pathIsPure: the path actually playing is Pure (`SignalPathInfo.path`).
    ///   - pureRequested: the Pure switch.
    public init(pathIsPure: Bool, pureRequested: Bool) {
        self = pathIsPure ? .notInBitPerfectMode(leaving: !pureRequested) : .live
    }

    /// Whether the row works.
    public var isLive: Bool {
        self == .live
    }

    /// The shared words — and what VoiceOver hears as an inert control's hint, after its own value (founder,
    /// 2026-10-30: "Off in bit-perfect mode"; "Not in bit-perfect mode" read as "Pure is off"; VoiceOver keeps the
    /// control's value and gives the state as a hint).
    public static let stateText = "Off in bit-perfect mode"
    /// The one action.
    public static let leaveAction = "Leave Pure"
    /// After Leave Pure, until the next start (the Pure switch's own timing, US-R1F-13).
    public static let leavingText = "Enhanced starts the next time you start a song."
}
