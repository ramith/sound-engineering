// EQSaveSource — what Save saves (Sprint EQ, EQ4; break-it C1). Taken when the Save sheet opens: the
// state on show and the slot it plays in. The output may switch while the sheet is up (AirPods
// connecting), moving `current` to another slot; Save still saves the curve the user was looking at,
// into the slot it came from, and the other output's slot is never touched.

public struct EQSaveSource: Equatable, Sendable {
    /// What played when the sheet opened: what the preset will play.
    public let state: EQState

    /// The slot it played in (`nil`: shared), which then plays the saved preset.
    let slotID: String?
}
