import Foundation

// MARK: - Control metrics (S10.8 D3 — the icon chip, the capsule switch and the header pills)

/// The shared small controls' metrics, in one place so every adopter — the Now Playing queue
/// header, Songs' Sort / Columns, the EQ switch later — draws the same control. The chip and switch
/// sizes are the realigned queue header's (`png/03`), moved here unchanged from
/// `DesignSystem.QueueHeader`; the pill height is the shipped Songs pills'. All are
/// Dynamic-Type-scaled where the controls read them.
enum ControlMetrics {
    /// The icon chip's side: a square with `DesignSystem.Radius.control` corners.
    static let chipSide: CGFloat = 28
    /// The icon chip's SF Symbol point size.
    static let chipSymbol: CGFloat = 12
    /// A capsule-switch segment's height; plus twice `switchTrackPadding`, the 24pt switch.
    static let segmentHeight: CGFloat = 20
    /// The switch track's inset around its segments.
    static let switchTrackPadding: CGFloat = 2
    /// The gap between two segments.
    static let segmentSpacing: CGFloat = 2
    /// A segment title's inset from the capsule's round ends.
    static let segmentTitleInset: CGFloat = 10
    /// The teal edge that marks an "on" chip and the selected segment: the state cue that is not the
    /// fill (R4-CHIP-04, R4-SEG-02).
    static let stateRingWidth: CGFloat = 1
    /// How far OUTSIDE a control its keyboard focus ring reaches (a 1pt gap, then the 2pt ring) —
    /// where the system focus ring it replaces sits, clear of the control's own edge.
    static let focusRingOutset: CGFloat = 3
    /// A pressed chip's opacity — the press answer of the pill and the footer play button.
    static let pressedOpacity = 0.6
    /// The header pills' height at the default text size — the filter pill, Songs' Sort and
    /// Columns pills and the large teal pill — so a header's pills stay one height; each scales it
    /// with Dynamic Type (relative to `.body`).
    static let pillHeight: CGFloat = 30
}
