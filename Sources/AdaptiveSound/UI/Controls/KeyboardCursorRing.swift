import SwiftUI

// MARK: - Keyboard cursor ring (S10.8 A3)

extension View {
    /// The keyboard focus indicator for the custom (non-`List`) lists — Songs, the queue, the
    /// playlist detail and the Library rail. Each switches the system focus effect off
    /// (`.focusEffectDisabled()`, which would otherwise outline the whole scroll area) and draws
    /// this 2pt `focusRing` on its CURSOR row instead: the row the arrow keys act on, shown only
    /// while the list holds key focus. The selection tint alone is ~1.2:1 against the card and
    /// absent with nothing selected — this ring clears 3:1 everywhere it can sit (R4-FOCUS).
    ///
    /// Apply it to the row's own card shape (pass the row's corner radius) BEFORE any outer
    /// padding: `strokeBorder` draws inside the shape, so the ring follows the row's card and
    /// stays inside the list's own insets. It stays mounted and toggles opacity with no
    /// animation — the ring jumps with the cursor (the native feel for arrow-key travel, and
    /// nothing moves under Reduce Motion) — and never takes hits or a VoiceOver element.
    func keyboardCursorRing(_ isVisible: Bool, cornerRadius: CGFloat) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(DesignSystem.Color.focusRing, lineWidth: 2)
                .opacity(isVisible ? 1 : 0)
                .animation(nil, value: isVisible)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
