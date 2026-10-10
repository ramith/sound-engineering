import SwiftUI

// MARK: - EQ Compare (Sprint EQ, EQ3 — decision 28, ui-plan §4.2)

/// Compare = press and hold to hear the song without the EQ, at matched loudness; let go to return.
/// While held the pill wears the active tone (teal edge, `controlActiveFill`) and keeps its label, so
/// nothing shifts.
///
/// - **Mouse:** press holds, release (anywhere) lets go.
/// - **Keyboard:** a Tab stop; hold Return (repeats ignored). Space stays play / pause. Losing key focus
///   lets go.
/// - **VoiceOver:** a toggle ("on" / "off"): activating latches Compare and says so; a second activation,
///   or VoiceOver focus leaving the pill, lets go.
///
/// The screen lets go on Esc, the window losing key, a tab change; the view model on any edit and an
/// output change — Compare can never stick on. Disabled while the EQ doesn't play (Off, Pure Mode, no
/// engine): there is nothing to compare.
struct EQCompareButton: View {
    @Environment(EQViewModel.self) private var eq
    @Environment(\.showsKeyboardFocus) private var showsKeyboardFocus

    @State private var isHovered = false
    @GestureState private var isHolding = false
    @FocusState private var isFocused: Bool
    @AccessibilityFocusState private var hasVoiceOverFocus: Bool

    var body: some View {
        pill
            .disabled(!eq.audible.canCompare)
            .help("Hold to hear the song without the EQ, at matched loudness")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Compare")
            .accessibilityValue(eq.isComparing ? "on" : "off")
            .accessibilityAddTraits([.isButton, .isToggle])
            .accessibilityHint("Hear the song without the EQ, at matched loudness")
            .accessibilityAction(.default, toggleLatch)
            .accessibilityFocused($hasVoiceOverFocus)
            .onChange(of: hasVoiceOverFocus) { _, focused in letGo(unless: focused) }
    }

    /// The face, held by the pointer or by Return on the focused pill.
    private var pill: some View {
        HeaderPillFace(content: Label("Compare", systemImage: "square.split.2x1"),
                       tone: eq.isComparing ? .active : .neutral, isHovered: isHovered, isPressed: false)
            .gesture(DragGesture(minimumDistance: 0).updating($isHolding) { _, holding, _ in holding = true })
            .onChange(of: isHolding) { _, holding in hold(holding) }
            .onHover { isHovered = $0 }
            .focusable(interactions: .activate)
            // Focused, the pill takes Space as well as Return, so the global play / pause gives way.
            .suppressesTransportSpace(while: $isFocused)
            .focusEffectDisabled()
            .keyboardFocusRing(isFocused && showsKeyboardFocus, around: Capsule())
            .onKeyPress(keys: [.return, .space], phases: [.down, .repeat, .up], action: holdKey)
            .onChange(of: isFocused) { _, focused in letGo(unless: focused) }
    }

    private func hold(_ holding: Bool) {
        if holding {
            eq.beginCompare()
        } else {
            eq.endCompare()
        }
    }

    /// Key or VoiceOver focus left the pill: a held (or latched) Compare lets go.
    private func letGo(unless focused: Bool) {
        if !focused {
            eq.endCompare()
        }
    }

    /// Return or Space held on the focused pill holds Compare; the release lets go. The key's repeats
    /// are taken and ignored, so a held key never beeps.
    private func holdKey(_ press: KeyPress) -> KeyPress.Result {
        if press.phase != .repeat {
            hold(press.phase == .down)
        }
        return .handled
    }

    /// VoiceOver's activation: latch Compare on (and say what it does), or let go.
    private func toggleLatch() {
        guard !eq.isComparing else {
            eq.endCompare()
            return
        }
        eq.beginCompare()
        if eq.isComparing {
            AccessibilityNotification.Announcement("Comparing: hearing the song without the EQ, matched loudness")
                .post()
        }
    }
}
