import SwiftUI

// MARK: - Queue Controls (S10.8 PR C — 28pt icon chips, realigned `png/03`)

struct PlaylistControlsView: View {
    @Environment(AudioViewModel.self) var viewModel
    let onJumpToNowPlaying: () -> Void
    @Binding var panelMode: QueuePanelMode

    var body: some View {
        HStack(spacing: 4) {
            // Clear Queue — Up Next only, and only when there's something to clear. Immediate
            // (no confirm, founder §3): the queue is cheap to rebuild and History is left intact.
            if panelMode == .upNext, !viewModel.queue.isEmpty {
                QueueIconButton(title: "Clear Queue", systemImage: "trash",
                                action: viewModel.clearPlaylist)
                    .help("Clear the queue (keeps History)")
            }

            QueueIconButton(title: "Shuffle", systemImage: "shuffle",
                            isOn: viewModel.shuffleEnabled,
                            action: viewModel.toggleShuffle)
                .accessibilityLabel("Shuffle: \(viewModel.shuffleEnabled ? "on" : "off")")
                .help("Shuffle: \(viewModel.shuffleEnabled ? "On" : "Off")")

            QueueIconButton(title: "Repeat",
                            systemImage: viewModel.repeatMode == 2 ? "repeat.1" : "repeat",
                            isOn: viewModel.repeatMode > 0,
                            action: viewModel.cycleRepeatMode)
                .accessibilityLabel("Repeat mode: \(["off", "all", "one"][viewModel.repeatMode])")
                .help(["Off", "All", "One"][viewModel.repeatMode])

            // Jump to now-playing — the owner's sequenced action (clear filter, THEN bump
            // the request-ID that triggers the list's scroll onChange).
            if viewModel.selectedTrackIndex != nil {
                QueueIconButton(title: "Jump to Now Playing", systemImage: "play.circle",
                                accented: true,
                                action: onJumpToNowPlaying)
                    .help("Jump to now playing")
            }
        }
    }
}

/// One 28×28 header chip: resting badge wash → hover lift → toggled-on accent tint with a
/// ring and an `accentText` glyph (all token'd, audited by R4-CHIP-01).
struct QueueIconButton: View {
    let title: String
    let systemImage: String
    var isOn: Bool = false
    /// An always-teal ACTION glyph (jump-to-now-playing) — accent identity without the
    /// toggled-on chip treatment.
    var accented: Bool = false
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: DesignSystem.QueueHeader.iconSymbol, weight: .medium))
            .foregroundStyle(isOn || accented ? DesignSystem.Color.accentText : Color.asLabelSecond)
            .frame(width: DesignSystem.QueueHeader.iconButton,
                   height: DesignSystem.QueueHeader.iconButton)
            .background {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.control, style: .continuous)
                    .fill(isOn ? DesignSystem.Color.controlActiveFill
                        : hovering ? DesignSystem.Color.controlHover : DesignSystem.Color.hoverWash)
            }
            .overlay {
                if isOn {
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.control, style: .continuous)
                        .strokeBorder(DesignSystem.Color.accent.opacity(0.3), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.control,
                                           style: .continuous))
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: - Queue mode switcher (Up Next / Recent — the mini capsule pair)

/// The realigned segmented pair: a small `tabTrack` capsule with a `segmentSelected` lift —
/// the tab strip's grammar at header scale. Replaces `.pickerStyle(.segmented)`.
struct QueueModeSwitcher: View {
    @Binding var panelMode: QueuePanelMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        .frame(height: DesignSystem.QueueHeader.segmentHeight)
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
