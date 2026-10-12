import DesignTokenKit
import LibraryStore
import SwiftUI

// MARK: - Detail page row (S10.8 E2/E3 — the album, artist and genre pages' song row)

/// One song on an album, artist or genre page, on the Library rows' card (`LibraryRowChrome`, as
/// Songs): its number, its title (and, on a genre page, "Artist · Album" under it) and its time —
/// a single-line row at the queue and playlist rows' 36 pt pitch, a two-line row at Songs' 48 pt
/// (`LibraryRowSize`). The playing row reads as on Songs — the number becomes the equalizer, the
/// title the accent.
/// Visual only and free of environment objects: the list owns selection, play, the menu, the keys
/// and the row's one VoiceOver element (`accessibilityLabel` / `accessibilityValue` below).
struct DetailTrackRow: View {
    let track: LibraryTrackDisplay
    let size: LibraryRowSize
    /// The page leads its rows with a number column (an album's or an artist's; not a genre's).
    let showsNumberColumn: Bool
    /// The track number in that column; nil leaves it blank (an untagged song among tagged ones).
    let number: Int?
    /// The line under the title ("" hides it).
    let secondary: String
    let isNowPlaying: Bool
    let isPlaybackActive: Bool
    let isSelected: Bool
    /// The list holds key focus and this is the row its keys act on (A3).
    let isKeyboardCursor: Bool

    /// The number column — Songs' # column, so a page's numbers sit where Songs' do.
    private static let numberWidth: CGFloat = 34
    /// Songs' gap between columns.
    private static let columnSpacing: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Self.columnSpacing) {
            if showsNumberColumn {
                numberCell
                    .frame(width: Self.numberWidth)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(DesignSystem.Font.body.weight(isNowPlaying ? .semibold : .regular))
                    .foregroundStyle(isNowPlaying ? DesignSystem.Color.accentTitle : DesignSystem.Color.label)
                if !secondary.isEmpty {
                    Text(secondary)
                        .font(DesignSystem.Font.caption)
                        .foregroundStyle(DesignSystem.Color.labelSecondary)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 0)
            Text(formatDuration(track.durationSeconds))
                .font(DesignSystem.Font.monoSmall)
                .foregroundStyle(DesignSystem.Color.labelTertiary(onSelectedRow: isSelected))
        }
        .libraryRowChrome(size, isNowPlaying: isNowPlaying, isSelected: isSelected,
                          isKeyboardCursor: isKeyboardCursor)
    }

    /// The equalizer on the playing row, else the track number — or nothing for a song without one.
    @ViewBuilder
    private var numberCell: some View {
        if isNowPlaying {
            MiniEqualizer(animating: pulseIsActive(isPlaying: isPlaybackActive, reduceMotion: reduceMotion))
        } else if let number {
            Text(number, format: .number.grouping(.never))
                .font(DesignSystem.Font.monoSmall)
                .foregroundStyle(DesignSystem.Color.labelTertiary(onSelectedRow: isSelected))
        } else {
            Color.clear // the column keeps its width, so the titles stay in line
        }
    }

    // MARK: VoiceOver

    /// The row's spoken name: its title, the line under it, and its time ("Jai Ho, A. R. Rahman ·
    /// Slumdog Millionaire, 5 min 19 sec").
    static func accessibilityLabel(for track: LibraryTrackDisplay, secondary: String) -> String {
        ([track.title] + (secondary.isEmpty ? [] : [secondary]) + [spokenDuration(track.durationSeconds)])
            .joined(separator: ", ")
    }

    /// The row's spoken value: its track number, and "Now playing" on the playing row — the equalizer
    /// is the only visual cue, which VoiceOver can't see.
    static func accessibilityValue(number: Int?, isNowPlaying: Bool) -> String {
        ((number.map { ["Track \($0)"] } ?? []) + (isNowPlaying ? ["Now playing"] : [])).joined(separator: ", ")
    }
}
