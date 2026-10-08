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

// MARK: - Queue mode switcher (Up Next / Recent — the mini capsule pair)

/// The realigned segmented pair: a small `tabTrack` capsule with a `segmentSelected` lift —
/// the tab strip's grammar at header scale. Replaces `.pickerStyle(.segmented)`. The
/// segment height is Dynamic-Type-scaled; the header row `fixedSize()`s this control so
/// its labels can never be the header's truncation victim.
struct QueueModeSwitcher: View {
    @Binding var panelMode: QueuePanelMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .callout)
    private var segmentHeight = DesignSystem.QueueHeader.segmentHeight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(QueuePanelMode.allCases) { mode in
                let selected = mode == panelMode
                Button {
                    panelMode = mode
                } label: {
                    Text(mode.pickerLabel)
                        .font(.callout.weight(selected ? .bold : .semibold))
                        .foregroundStyle(selected ? Color.asLabel : Color.asLabelSecond)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: segmentHeight)
                        .background {
                            if selected {
                                Capsule().fill(DesignSystem.Color.segmentSelected)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(DesignSystem.QueueHeader.segmentPadding)
        .background(TabTrackCapsule())
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: panelMode)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Queue view")
        .accessibilityValue(panelMode.pickerLabel)
    }
}
