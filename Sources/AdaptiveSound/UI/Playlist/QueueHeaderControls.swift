import SwiftUI

// MARK: - Queue Controls (S10.8 PR C — the header's icon chips, realigned `png/03`; D3 — `IconChip`)

struct PlaylistControlsView: View {
    @Environment(AudioViewModel.self) var viewModel
    let onJumpToNowPlaying: () -> Void
    @Binding var panelMode: QueuePanelMode

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xSmall) {
            // Clear Queue — Up Next only, and only when there's something to clear. Immediate
            // (no confirm, founder §3): the queue is cheap to rebuild and History is left intact.
            // Tooltips and VoiceOver hints are the chip's own (`IconChip`): a hint only where the
            // title and value don't already say what pressing does.
            if panelMode == .upNext, !viewModel.queue.isEmpty {
                IconChip("Clear Queue", systemImage: "trash", help: "Clear the queue (keeps History)",
                         hint: "Empties the queue. History is kept.", action: viewModel.clearPlaylist)
            }

            IconChip("Shuffle", systemImage: "shuffle", isOn: viewModel.shuffleEnabled,
                     value: shuffleName, action: viewModel.toggleShuffle)

            IconChip("Repeat", systemImage: viewModel.repeatMode == 2 ? "repeat.1" : "repeat",
                     isOn: viewModel.repeatMode > 0, value: repeatName,
                     hint: "Steps through off, all and one.", action: viewModel.cycleRepeatMode)

            // Jump to now-playing — the owner's sequenced action (clear filter, THEN bump
            // the request-ID that triggers the list's scroll onChange).
            if viewModel.selectedTrackIndex != nil {
                IconChip("Jump to Now Playing", systemImage: "play.circle", emphasis: .accented,
                         hint: "Clears the filter and scrolls the queue to the playing track.",
                         action: onJumpToNowPlaying)
            }
        }
    }

    private var shuffleName: String {
        viewModel.shuffleEnabled ? "On" : "Off"
    }

    /// `AudioViewModel.repeatMode`: 0 off, 1 all, 2 one.
    private var repeatName: String {
        switch viewModel.repeatMode {
        case 1: "All"
        case 2: "One"
        default: "Off"
        }
    }
}
