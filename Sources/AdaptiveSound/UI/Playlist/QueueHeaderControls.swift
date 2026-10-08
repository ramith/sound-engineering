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
            if panelMode == .upNext, !viewModel.queue.isEmpty {
                IconChip("Clear Queue", systemImage: "trash", action: viewModel.clearPlaylist)
                    .help("Clear the queue (keeps History)")
            }

            IconChip("Shuffle", systemImage: "shuffle", isOn: viewModel.shuffleEnabled,
                     value: shuffleName, action: viewModel.toggleShuffle)
                .help("Shuffle: \(shuffleName)")

            IconChip("Repeat", systemImage: viewModel.repeatMode == 2 ? "repeat.1" : "repeat",
                     isOn: viewModel.repeatMode > 0, value: repeatName, action: viewModel.cycleRepeatMode)
                .help("Repeat: \(repeatName)")

            // Jump to now-playing — the owner's sequenced action (clear filter, THEN bump
            // the request-ID that triggers the list's scroll onChange).
            if viewModel.selectedTrackIndex != nil {
                IconChip("Jump to Now Playing", systemImage: "play.circle", emphasis: .accented,
                         action: onJumpToNowPlaying)
                    .help("Jump to now playing")
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
