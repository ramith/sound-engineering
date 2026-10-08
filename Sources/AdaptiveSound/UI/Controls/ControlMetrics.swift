import Foundation

// MARK: - Control metrics (S10.8 D3 — the icon chip and the capsule switch)

/// The shared small controls' metrics, in one place so every adopter — the Now Playing queue header
/// today, Songs' Sort / Columns and the EQ switch later — draws the same control. The sizes are the
/// realigned queue header's (`png/03`), moved here unchanged from `DesignSystem.QueueHeader`; the
/// sizes are Dynamic-Type-scaled where the controls read them.
enum ControlMetrics {
    /// The icon chip's side: a square with `DesignSystem.Radius.control` corners.
    static let chipSide: CGFloat = 28
    /// The icon chip's SF Symbol point size.
    static let chipSymbol: CGFloat = 12
    /// The teal edge that marks an "on" chip: the state cue that is not the fill (R4-CHIP-04).
    static let stateRingWidth: CGFloat = 1
    /// How far OUTSIDE a control its keyboard focus ring reaches (a 1pt gap, then the 2pt ring) —
    /// where the system focus ring it replaces sits, clear of the control's own edge.
    static let focusRingOutset: CGFloat = 3
    /// A pressed chip's opacity — the press answer of the pill and the footer play button.
    static let pressedOpacity = 0.6
}
