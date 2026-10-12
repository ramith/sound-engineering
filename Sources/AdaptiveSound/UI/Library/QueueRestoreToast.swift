import SwiftUI

// MARK: - Queue restore toast (S10.8 E review 18 — the Library card's one undo for a queue replace)

/// "Queue replaced · Restore previous queue" at the foot of the Library card — mounted ONCE, by
/// `LibraryTabView`, for every Library page whose play replaced the queue (an album's, artist's,
/// genre's or playlist's Play, Shuffle and row plays, and a tile's Play: `LibraryBrowseModel
/// .offerQueueRestore`). It shows while its slot (`restoreToast`, about six seconds) is up and the
/// queue's restore point stands; restoring brings the previous queue and shuffle setting back
/// (`AudioViewModel.restorePreviousQueue`). The playlist page's former toast, moved here unchanged:
/// a capsule on the `.overlay` glass (Regime A — it floats over the list) with a hairline.
struct QueueRestoreToast: View {
    @Environment(LibraryBrowseModel.self) private var model
    @Environment(AudioViewModel.self) private var audio

    var body: some View {
        if let toast = model.restoreToast.toast, audio.canRestorePreviousQueue {
            HStack(spacing: DesignSystem.Spacing.medium) {
                Text(toast.message)
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(DesignSystem.Color.label)
                Button("Restore previous queue", action: restore)
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignSystem.Color.accentForeground)
            }
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .padding(.vertical, DesignSystem.Spacing.small)
            // Regime A/`.overlay` (S10.7 §3.1): a restore-toast floating over the list. The `.bar`
            // substrate preserves this pill's shipped look exactly.
            .glassPanel(.overlay(.bar), in: Capsule())
            .overlay(Capsule().stroke(DesignSystem.Color.hairline, lineWidth: 0.5))
            .padding(.bottom, DesignSystem.Spacing.large)
            .transition(.opacity)
        }
    }

    private func restore() {
        audio.restorePreviousQueue()
        model.restoreToast.dismiss()
    }
}
