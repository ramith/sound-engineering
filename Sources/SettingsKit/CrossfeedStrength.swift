// CrossfeedStrength — the crossfeed strengths the listener chooses between, as a setting: the values
// `ListeningSettings` keeps and reads back (an unknown one reads as `defaultStrength`). The app maps each
// to its label and to the DSP kernel's coefficient set (`Models/CrossfeedStrength.swift`).

/// The crossfeed strength the listener chose. The raw value is what is stored, and the C++ kernel's
/// `CrossfeedPreset` index (Relaxed = 0, Bauer = 1 — "Default" to the user — Strong = 2).
public enum CrossfeedStrength: Int, CaseIterable, Identifiable, Sendable {
    case relaxed = 0
    case defaultStrength = 1
    case strong = 2

    public var id: Int {
        rawValue
    }
}
