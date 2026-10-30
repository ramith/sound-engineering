import SettingsKit
import SwiftUI

// MARK: - Leave Pure (R1.1-B, US-R1F-20: the one action of the shared Pure row state)

/// "Leave Pure" — the one action wherever Pure makes a control inert: every DSP row's note (`BitPerfectRowNote`)
/// and the EQ graph's strip (founder, 2026-10-30: one name, one view, for one action). Pressed, it turns the Pure
/// switch off, which takes effect the next time a song is started (US-R1F-13); until then it gives way to the words
/// that say so. A link-style button with the app's keyboard ring.
struct LeavePureAction: View {
    /// The listener has switched Pure off already: Enhanced comes back at the next start.
    let leaving: Bool
    /// Leave Pure: the switch off (`AudioViewModel.leavePure`).
    let leavePure: () -> Void

    var body: some View {
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
