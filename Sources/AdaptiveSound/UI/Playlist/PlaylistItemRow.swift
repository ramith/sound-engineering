import SwiftUI

// MARK: - Playlist Item Row

struct PlaylistItemRow: View {
    let file: AudioFile
    let index: Int
    let isSelected: Bool
    let isNowPlaying: Bool
    /// Width of the track-number column, sized by the caller to the widest number in the
    /// list so 3-/4-digit indices (track 100+) fit on one line instead of wrapping.
    var numberColumnWidth: CGFloat = 22

    var body: some View {
        HStack(spacing: 12) {
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
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? Color.asAccent : Color.asLabelTertiary)
                }
            }
            .frame(width: numberColumnWidth, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.asAccent : Color.asLabel)
                    .lineLimit(1)

                Text(file.relativePath)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.asLabelTertiary)
                    .lineLimit(1)
            }

            Spacer()

            FormatBadgeView(format: file.format, isSelected: isSelected)

            Text(file.durationSeconds > 0 ? formatDuration(file.durationSeconds) : "--:--")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.asLabelTertiary)
                .frame(width: 42, alignment: .trailing)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowBackground(
            isNowPlaying
                ? Color.asAccent.opacity(0.25)
                : isSelected
                ? Color.asAccent.opacity(0.12)
                : Color.clear
        )
        .contentShape(Rectangle())
        // One VoiceOver element per row (A-M3): a clean label (title · format · duration — NOT the
        // noisy `relativePath` the auto-composed label pulled in), with now-playing/selected exposed
        // as a value + trait rather than color alone. `.isButton` is added by the enclosing list.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isNowPlaying ? "Now playing" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityLabel: String {
        var parts = [file.name, file.format]
        if file.durationSeconds > 0 { parts.append(formatDuration(file.durationSeconds)) }
        return parts.joined(separator: ", ")
    }
}
