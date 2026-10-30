import SettingsKit
import SwiftUI

// MARK: - The shared "Not in bit-perfect mode" row state (R1.1-B, US-R1F-20 items 1–2)

//
// ONE state for every control that changes the sound in the app's engine — the registry is SettingsKit's
// `DSPRow` — so nothing looks broken while Pure plays and the listener knows what leaving Pure buys. A row wears it
// in two parts, both named by its `DSPRow`, so a row cannot wear one without being registered (and the registry test
// fails a registered row that wears neither):
//
// - `bitPerfectGate(_:_:)` on the control: inert while the path in use is Pure (the rule is
//   `DSPRowAvailability`, following `SignalPathInfo.path`, never the switch alone), dimmed the way every disabled
//   control dims, and VoiceOver reads "unavailable, not in bit-perfect mode" as its value;
// - `BitPerfectRowNote` beside it: the row's words — "Not in bit-perfect mode", or Leveling's own "Leveling off
//   (bit-perfect)" — with the one action, Leave Pure; after it, until the next start, when Enhanced comes back.

extension View {
    /// Gate this DSP control, registered as `row`, by `availability` (`AudioViewModel.dspRowAvailability`).
    func bitPerfectGate(_ row: DSPRow, _ availability: DSPRowAvailability) -> some View {
        modifier(BitPerfectGate(row: row, isLive: availability.isLive))
    }
}

/// One structure in both states: the path flipping changes the modifiers' values, never the control's identity —
/// a rebuilt control would lose its drag (an open Tone stroke), its keyboard focus and VoiceOver's cursor
/// (review-ui M1). No tooltip of its own: the note beside the control says the same words, and an outer `help`
/// would hide the control's own (Reset Tone's).
private struct BitPerfectGate: ViewModifier {
    let row: DSPRow
    let isLive: Bool

    func body(content: Content) -> some View {
        content
            .disabled(!isLive) // an outer `false` never re-enables a control its own `disabled` holds off
            .disabledDim(!isLive)
            .accessibilityValue(DSPRowAvailability.spokenState, isEnabled: !isLive)
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
                    words
                    action(leaving: leaving)
                }
                VStack(alignment: .leading, spacing: 2) {
                    words
                    action(leaving: leaving)
                }
            }
            .font(DesignSystem.Font.caption)
        }
    }

    /// The row's words. VoiceOver hears them as the gated control's value, so not twice.
    private var words: some View {
        Text(row.bitPerfectText)
            .foregroundStyle(DesignSystem.Color.labelSecondary)
            .fixedSize()
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
            Button(DSPRowAvailability.leaveAction, action: leavePure)
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Color.accentForeground)
                // A Tab stop under Full Keyboard Access: the app's teal ring, never the system's (blue) one.
                .controlFocusRing(around: RoundedRectangle(cornerRadius: DesignSystem.Radius.control))
                .pointerStyle(.link)
                .fixedSize()
                .accessibilityHint("Plays through Enhanced from the next song you start")
        }
    }
}
