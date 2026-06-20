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
            Text(index + 1, format: .number.grouping(.never))
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.asAccent : Color.asLabelTertiary)
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

            Text(file.format)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isSelected ? Color.asAccent.opacity(0.2) : Color.asCard)
                .foregroundStyle(isSelected ? Color.asAccent : Color.asLabelSecond)
                .clipShape(.rect(cornerRadius: 4, style: .continuous))

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
    }
}
