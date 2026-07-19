import SwiftUI

// MARK: - Playlist Item Row

struct PlaylistItemRow<DragPayload: Transferable>: View {
    let file: AudioFile
    let index: Int
    let isSelected: Bool
    let isNowPlaying: Bool
    /// Width of the track-number column, sized by the caller to the widest number in the
    /// list so 3-/4-digit indices (track 100+) fit on one line instead of wrapping.
    var numberColumnWidth: CGFloat = 22
    /// When non-nil, the row shows a leading grip that is the DRAG SOURCE for reordering
    /// (`.draggable`). Making only the grip draggable — not the whole row — keeps tap-to-play
    /// unambiguous (the row-wide gesture conflict is what killed `.onMove`, FB7367473). Nil shows
    /// no handle and is not reorderable. Generic over the payload so the queue reuses this row with
    /// a `QueueDragItem` and the playlist detail with a `PlaylistEntryDragItem` (S10.3, architect
    /// review) — one row, no fork.
    var dragPayload: DragPayload?
    /// True while a reorder drag is hovering over THIS row (the drop target). Draws an accent
    /// border so the drop point is visible during the drag (macOS drop-zone affordance).
    var isDropTarget: Bool = false

    /// Row hover reveals the drag grip (S10.8 PR C — realigned: no handles at rest). The
    /// grip stays MOUNTED at opacity 0 (hidden, not removed): it keeps its leading slot (no
    /// reflow on hover) and stays a live drag source, so reorder works even mid-fade.
    @State private var isRowHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            if let dragPayload {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: DesignSystem.QueueRow.gripSymbol))
                    .foregroundStyle(Color.asLabelTertiary)
                    // Larger hit area than the thin glyph itself.
                    .frame(width: DesignSystem.QueueRow.gripHitWidth, height: DesignSystem.QueueRow.gripHitHeight)
                    .contentShape(Rectangle())
                    .opacity(isRowHovered ? DesignSystem.QueueRow.gripHoverOpacity : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isRowHovered)
                    .draggable(dragPayload) {
                        Text(file.name)
                            .font(DesignSystem.Font.body)
                            .lineLimit(1)
                            .padding(.horizontal, DesignSystem.Spacing.small)
                            .padding(.vertical, DesignSystem.Spacing.xSmall)
                            .background(
                                DesignSystem.Color.rowNowPlaying,
                                in: RoundedRectangle(cornerRadius: DesignSystem.Radius.control)
                            )
                    }
                    .help("Drag to reorder")
                    .accessibilityHidden(true) // the context-menu Move commands are the a11y path
            }
            // Non-color now-playing cue (A-M3): the currently-playing row shows a ▶ glyph in place
            // of its number, so "now playing" is not signalled by the row tint alone (colorblind /
            // VoiceOver users get no cue from the background opacity otherwise).
            Group {
                if isNowPlaying {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.asAccent)
                } else {
                    Text(index + 1, format: .number.grouping(.never))
                        .font(DesignSystem.Font.monoSmall)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? Color.asAccent : Color.asLabelTertiary)
                }
            }
            .frame(width: numberColumnWidth, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(DesignSystem.Font.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.asAccent : Color.asLabel)
                    .lineLimit(1)

                Text(file.relativePath)
                    .font(DesignSystem.Font.monoSmall)
                    .foregroundStyle(Color.asLabelTertiary)
                    .lineLimit(1)
            }

            Spacer()

            FormatBadgeView(format: file.format, isSelected: isSelected)

            Text(file.durationSeconds > 0 ? formatDuration(file.durationSeconds) : "--:--")
                .font(DesignSystem.Font.monoSmall)
                .foregroundStyle(Color.asLabelTertiary)
                .frame(width: DesignSystem.QueueRow.durationWidth, alignment: .trailing)
        }
        // Self-styled row (padding + background) so it renders identically whether it sits in a
        // `List` or — as of the S10.2 drag-reorder rewrite — a `LazyVStack` (where `.listRow*`
        // modifiers are no-ops). `.dropDestination` doesn't fire inside a `List`, so the queue moved
        // to a ScrollView/LazyVStack; the row owns its own insets + selection/now-playing tint.
        .padding(.vertical, DesignSystem.Spacing.xSmall)
        .padding(.horizontal, DesignSystem.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowTint)
        .overlay {
            if isDropTarget {
                Rectangle().strokeBorder(DesignSystem.Color.accent, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { isRowHovered = $0 }
        // Full file-path tooltip (deviations §3) — the honest provenance readout on hover;
        // `AudioFile.id` IS the absolute URL.
        .help(file.id.path)
        // One VoiceOver element per row (A-M3): a clean label (title · format · duration — NOT the
        // noisy `relativePath` the auto-composed label pulled in), with now-playing/selected exposed
        // as a value + trait rather than color alone. `.isButton` is added by the enclosing list.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isNowPlaying ? "Now playing" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Row-fill tint: now-playing > selected > none (matches the former `.listRowBackground`).
    private var rowTint: Color {
        if isNowPlaying {
            DesignSystem.Color.rowNowPlaying
        } else if isSelected {
            DesignSystem.Color.rowSelected
        } else {
            Color.clear
        }
    }

    private var accessibilityLabel: String {
        var parts = [file.name, file.format]
        if file.durationSeconds > 0 { parts.append(formatDuration(file.durationSeconds)) }
        return parts.joined(separator: ", ")
    }
}
