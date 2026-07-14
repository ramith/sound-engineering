import Foundation
import LibraryStore
import SwiftUI

// MARK: - Recently Played row (S10.6)

/// One row of the Recently-Played (frecency) tab, bound to a `LibraryTrackDisplay` (durable id,
/// artwork, play stats) — deliberately NOT the `AudioFile`-based `PlaylistItemRow` (wrong input +
/// different anatomy). Leading artwork, title + format badge, and the **"N plays · «relative
/// last-played»"** cue in place of the (blank) subtitle so the frecency ordering reads as
/// intentional. No rank number, no duration. Tapping plays it now (wired by the list).
struct RecentlyPlayedRow: View {
    @Environment(LibraryBrowseModel.self) private var model
    let track: LibraryTrackDisplay
    /// The currently-playing track matches this row (shows the ▶ cue + accent tint).
    let isNowPlaying: Bool

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            AlbumArtworkView(key: track.artworkKey, side: DesignSystem.SongsList.artwork, model: model)
                .overlay {
                    if isNowPlaying {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(DesignSystem.Color.onAccent)
                            .padding(3)
                            .background(DesignSystem.Color.accent, in: Circle())
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(DesignSystem.Font.body.weight(isNowPlaying ? .semibold : .regular))
                    .foregroundStyle(isNowPlaying ? Color.asAccent : Color.asLabel)
                    .lineLimit(1)
                Text(statsCue)
                    .font(DesignSystem.Font.monoSmall)
                    .foregroundStyle(Color.asLabelTertiary)
                    .lineLimit(1)
            }

            Spacer()

            FormatBadgeView(format: track.format, isSelected: isNowPlaying)
        }
        .padding(.vertical, DesignSystem.Spacing.xSmall)
        .padding(.horizontal, DesignSystem.Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isNowPlaying ? DesignSystem.Color.rowNowPlaying : Color.clear)
        .contentShape(Rectangle())
        // One VoiceOver element per row: title · play count · relative last-played, now-playing as a
        // value + button trait (activation wired by the list's `.accessibilityAction`).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isNowPlaying ? "Now playing" : "")
        .accessibilityAddTraits(.isButton)
    }

    /// "12 plays · 2 hours ago" (or "1 play" / just the count if never-stamped, which can't happen
    /// for a played row). Relative time is localized via `Date.RelativeFormatStyle`.
    private var statsCue: String {
        let plays = "\(track.playCount) play\(track.playCount == 1 ? "" : "s")"
        guard let lastPlayed = track.lastPlayed else { return plays }
        return "\(plays) · \(relativeString(fromEpochSeconds: lastPlayed))"
    }

    private var accessibilityLabel: String {
        var parts = [track.title, "\(track.playCount) play\(track.playCount == 1 ? "" : "s")"]
        if let lastPlayed = track.lastPlayed {
            parts.append("last played " + relativeString(fromEpochSeconds: lastPlayed))
        }
        return parts.joined(separator: ", ")
    }

    private func relativeString(fromEpochSeconds seconds: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(seconds)).formatted(.relative(presentation: .named))
    }
}
