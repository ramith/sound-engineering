import DesignTokenKit
import LibraryStore
import SwiftUI

// MARK: - Songs row (S10.8 Library PR-D — `png/04`/`png/05` default, `png/06`/`07` columns)

/// One row of the Twin Panels song list. Renders an ORDERED set of visible columns (the frozen
/// # + Title group first, then the metadata columns) at their fixed widths — Title is the one
/// flexible column (the caller passes its resolved width). Visual only + ENV-FREE: the list owns
/// selection, play, the context menu, keyboard, and the row's single VoiceOver element, keeping
/// this row off any `@Environment(Observable)` a11y host. No artwork / no play-triangle — the
/// #/equalizer column is the sole now-playing indicator (explicit design decision).
struct SongRow: View {
    let track: LibraryTrackDisplay
    /// 1-based position in the visible list (the mock's leading number, not `trackNo`).
    let number: Int
    /// The visible columns in order (includes the frozen `.index` + `.title`).
    let columns: [SongColumn]
    /// Resolved width for the flexible Title column (fills when the set fits, else `titleMinWidth`).
    let titleWidth: CGFloat
    let isNowPlaying: Bool
    let isPlaybackActive: Bool
    let isSelected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false

    var body: some View {
        HStack(spacing: 14) {
            ForEach(columns) { column in
                cell(for: column)
                    .frame(width: width(for: column), alignment: alignment(for: column))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(rowFill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            if isNowPlaying {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(DesignSystem.Color.accent.opacity(0.36), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }

    private func width(for column: SongColumn) -> CGFloat {
        column == .title ? titleWidth : (column.width ?? SongColumn.titleMinWidth)
    }

    private func alignment(for column: SongColumn) -> Alignment {
        if column == .index {
            return .center
        }
        return column.isTrailing ? .trailing : .leading
    }

    private var rowFill: Color {
        if isNowPlaying {
            DesignSystem.Color.rowNowPlaying
        } else if isSelected {
            DesignSystem.Color.rowSelected
        } else if hover {
            DesignSystem.Color.controlHover
        } else {
            .clear
        }
    }

    // MARK: Cells

    @ViewBuilder
    private func cell(for column: SongColumn) -> some View {
        switch column {
        case .index: indexCell
        case .title: titleCell
        default:
            Text(column.displayText(track))
                .font(column.isMono ? DesignSystem.Font.monoSmall : DesignSystem.Font.body)
                .foregroundStyle(cellColor(column))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// Quality leads with the accent when playing (else secondary); other mono columns are tertiary,
    /// text columns secondary.
    private func cellColor(_ column: SongColumn) -> Color {
        if column == .quality {
            return isNowPlaying ? DesignSystem.Color.accentText : DesignSystem.Color.labelSecondary
        }
        return column.isMono ? DesignSystem.Color.labelTertiary : DesignSystem.Color.labelSecondary
    }

    @ViewBuilder
    private var indexCell: some View {
        if isNowPlaying {
            MiniEqualizer(animating: pulseIsActive(isPlaying: isPlaybackActive,
                                                   reduceMotion: reduceMotion))
        } else {
            Text(number, format: .number.grouping(.never))
                .font(DesignSystem.Font.monoSmall)
                .foregroundStyle(DesignSystem.Color.labelTertiary)
        }
    }

    private var titleCell: some View {
        HStack(spacing: 9) {
            Text(track.title)
                .font(DesignSystem.Font.body.weight(isNowPlaying ? .semibold : .regular))
                .foregroundStyle(isNowPlaying ? DesignSystem.Color.accentTitle : DesignSystem.Color.label)
                .lineLimit(1)
                .truncationMode(.tail)
            FormatBadgeView(format: track.format, isSelected: isNowPlaying)
            Spacer(minLength: 0)
        }
    }
}
