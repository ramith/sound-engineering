import SwiftUI

// MARK: - Shell toasts (Sprint EQ, EQ4 — break-it 8)

/// The shell's bottom-centre toasts, overlaid on the content region on every tab: Pure's "Volume restored"
/// (R1.1-B) and the EQ's output switch stacked over the queue-add confirmation. Raised together they sit one
/// above the other instead of on top of each other; one alone sits where any always has, since an idle host takes
/// no room.
struct ShellToasts: View {
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.small) {
            VolumeRestoredToast()
            EQOutputToast()
            QueueToast()
        }
        .padding(.bottom, DesignSystem.Spacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
