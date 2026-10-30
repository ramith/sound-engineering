import SettingsKit
import SwiftUI

// MARK: - The shared "Off in bit-perfect mode" row state (R1.1-B, US-R1F-20 items 1–2)

//
// ONE state for every control that changes the sound in the app's engine — the registry is SettingsKit's
// `DSPRow` — so nothing looks broken while Pure plays and the listener knows what leaving Pure buys. A row wears it
// in two parts, both named by its `DSPRow`, so a row cannot wear one without being registered (and the registry test
// fails a registered row that wears neither):
//
// - `bitPerfectGate(_:_:)` on the control: inert while the path in use is Pure (the rule is
//   `DSPRowAvailability`, following `SignalPathInfo.path`, never the switch alone), dimmed the way every disabled
//   control dims; VoiceOver keeps the control's own value ("Leveling, Auto, dimmed") and hears "Off in bit-perfect
//   mode" as its hint (founder, 2026-10-30);
// - `BitPerfectRowNote` beside it: the row's words — "Off in bit-perfect mode", or Leveling's own "Leveling off
//   (bit-perfect)" — with the one action, Leave Pure; after it, until the next start, when Enhanced comes back.

extension View {
    /// Gate this DSP control, registered as `row`, by `availability` (`AudioViewModel.dspRowAvailability`).
    /// `ownDisabledLook`: the control draws its own disabled look — the pills, the graph's not-playing curve, a switch
    /// whose segments dim themselves — so the gate never dims it again on top.
    func bitPerfectGate(_ row: DSPRow, _ availability: DSPRowAvailability, ownDisabledLook: Bool = false) -> some View {
        modifier(BitPerfectGate(row: row, isLive: availability.isLive, dims: !ownDisabledLook))
    }
}

/// One structure in both states: the path flipping changes the modifiers' values, never the control's identity —
/// a rebuilt control would lose its drag (an open Tone stroke), its keyboard focus and VoiceOver's cursor
/// (review-ui M1). No tooltip of its own: the note beside the control says the same words, and an outer `help`
/// would hide the control's own (Reset Tone's).
private struct BitPerfectGate: ViewModifier {
    let row: DSPRow
    let isLive: Bool
    /// The gate dims the inert control (dark 50%, `disabledDim`); not one that draws its own disabled look.
    let dims: Bool

    func body(content: Content) -> some View {
        content
            .disabled(!isLive) // an outer `false` never re-enables a control its own `disabled` holds off
            .disabledDim(dims && !isLive)
            // The control keeps its value (the setting that applies the moment Pure is left); the state is the hint.
            .accessibilityHint(DSPRowAvailability.stateText, isEnabled: !isLive)
            // Its registry name, for Accessibility Inspector and the live UI checks: "dsp.equalizer", "dsp.tone", …
            .accessibilityIdentifier("dsp.\(row.rawValue)")
    }
}

/// The words under (or beside) a DSP row while Pure plays, and its one action; nothing while the row works. One
/// line where it fits, its action under its words where it doesn't (a narrow rail card).
struct BitPerfectRowNote: View {
    let row: DSPRow
    let availability: DSPRowAvailability
    /// Leave Pure: the switch off (`AudioViewModel.leavePure`).
    let leavePure: () -> Void

    var body: some View {
        if case let .notInBitPerfectMode(leaving) = availability {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.small) {
                    words.fixedSize()
                    action(leaving: leaving)
                }
                // Stacked, the words wrap: a narrow rail card (and a larger text size) must never run them past its
                // edge — ViewThatFits takes this last child even where it doesn't fit (review-ui S6).
                VStack(alignment: .leading, spacing: 2) {
                    words.fixedSize(horizontal: false, vertical: true)
                    action(leaving: leaving)
                }
            }
            .font(DesignSystem.Font.caption)
        }
    }

    /// The row's words. VoiceOver hears the shared state as the gated control's hint, so not twice.
    private var words: some View {
        Text(row.bitPerfectText)
            .foregroundStyle(DesignSystem.Color.labelSecondary)
            .accessibilityHidden(true)
    }

    /// Leave Pure; once pressed, when Enhanced comes back (the Pure switch's own timing).
    @ViewBuilder
    private func action(leaving: Bool) -> some View {
        if leaving {
            Text(DSPRowAvailability.leavingText)
                .foregroundStyle(DesignSystem.Color.labelTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Button(DSPRowAvailability.leaveAction, action: leave)
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Color.accentForeground)
                // A Tab stop under Full Keyboard Access: the app's teal ring, never the system's (blue) one.
                .controlFocusRing(around: RoundedRectangle(cornerRadius: DesignSystem.Radius.control))
                .pointerStyle(.link)
                .fixedSize()
                .accessibilityHint("Plays through Enhanced from the next song you start")
        }
    }

    /// Leave Pure, and say what happens: the button gives way to the leaving words, so the element under
    /// VoiceOver's cursor (and the keyboard focus) goes — the announcement is the confirmation, as a toast's is
    /// (`ShellToastHost.announce()`; review-ui S1).
    private func leave() {
        leavePure()
        AccessibilityNotification.Announcement(DSPRowAvailability.leavingText).post()
    }
}
