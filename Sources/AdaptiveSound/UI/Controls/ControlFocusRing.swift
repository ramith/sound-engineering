import SwiftUI

// MARK: - Control focus ring (S10.8 D3 — the keyboard ring of a control that is a Tab stop)

extension View {
    /// The app's keyboard ring on a control that is a Tab stop of its own under Full Keyboard
    /// Access — the icon chip, the capsule switch, Songs' Sort and Columns pills — in place of the
    /// system focus effect. It follows the control's own key focus and shows only while the window
    /// is keyboard-driven (`showsKeyboardFocus`), so a click never leaves a ring behind; drawn
    /// outside `shape` by `keyboardFocusRing(_:around:)`.
    ///
    /// Apply it to the focusable control itself (after `.focusable(…)` where the control needs
    /// one), so it binds the control's focus rather than a container's.
    func controlFocusRing(around shape: some InsettableShape) -> some View {
        modifier(ControlFocusRing(shape: shape))
    }
}

/// `controlFocusRing(around:)`: the control's key focus and the window's keyboard mode, held for
/// the ring.
private struct ControlFocusRing<RingShape: InsettableShape>: ViewModifier {
    let shape: RingShape

    @FocusState private var isFocused: Bool
    @Environment(\.showsKeyboardFocus) private var showsKeyboardFocus

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .focusEffectDisabled()
            .keyboardFocusRing(isFocused && showsKeyboardFocus, around: shape)
    }
}
