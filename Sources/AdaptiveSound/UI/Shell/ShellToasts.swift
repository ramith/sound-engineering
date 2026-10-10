import SwiftUI

// MARK: - Shell toasts (Sprint EQ, EQ4 — break-it 8)

/// The shell's bottom-centre toasts, overlaid on the content region on every tab: the EQ's output switch
/// stacked over the queue-add confirmation. Two raised together sit one above the other instead of on
/// top of each other; one alone sits where either always has, since an idle host takes no room.
struct ShellToasts: View {
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.small) {
            EQOutputToast()
            QueueToast()
        }
        .padding(.bottom, DesignSystem.Spacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
