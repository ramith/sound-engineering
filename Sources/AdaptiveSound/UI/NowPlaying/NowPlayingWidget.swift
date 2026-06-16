import SwiftUI

// MARK: - Now Playing Widget

/// Compact card showing the current track's artwork placeholder, name, and progress bar.
struct NowPlayingWidget: View {
    @Environment(AudioViewModel.self) var viewModel

    var body: some View {
        if let selectedIndex = viewModel.selectedTrackIndex,
           selectedIndex < viewModel.playlist.count
        {
            let currentTrack = viewModel.playlist[selectedIndex]
            TrackCard(track: currentTrack, position: viewModel.playbackPosition)
        } else {
            EmptyTrackCard()
        }
    }
}

// MARK: - Track Card

private struct TrackCard: View {
    let track: AudioFile
    let position: Double

    /// Fraction of the track elapsed, clamped to [0, 1].
    private var progressFraction: Double {
        guard track.durationSeconds > 0 else { return 0 }
        return min(max(position / track.durationSeconds, 0), 1)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.asAccent)
                    .frame(width: 52, height: 52)
                    .background(Color.asWindow)
                    .clipShape(.rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.asLabel)
                        .lineLimit(1)

                    Text("Unknown Artist")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.asLabelSecond)
                        .lineLimit(1)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                Text(formatDuration(position))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.asLabelTertiary)
                    .monospacedDigit()

                // Progress bar — GeometryReader scales the fill proportionally to
                // the container width, which is a legitimate use case.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.asCard)

                        Capsule()
                            .fill(Color.asAccent)
                            .frame(width: geo.size.width * CGFloat(progressFraction))
                    }
                }
                .frame(height: 3)

                Text(track.durationSeconds > 0 ? formatDuration(track.durationSeconds) : "--:--")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.asLabelTertiary)
            }
        }
        .padding(12)
        .background(Color.asWindow)
        .clipShape(.rect(cornerRadius: 8))
    }
}

// MARK: - Empty Track Card

private struct EmptyTrackCard: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.asLabelTertiary)
                    .frame(width: 52, height: 52)
                    .background(Color.asCard)
                    .clipShape(.rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("No track selected")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.asLabelSecond)
                        .lineLimit(1)

                    Text("Click a track to play")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.asLabelTertiary)
                        .lineLimit(1)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                Text("--:--")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.asLabelTertiary)

                GeometryReader { _ in
                    Capsule()
                        .fill(Color.asCard)
                }
                .frame(height: 3)

                Text("--:--")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.asLabelTertiary)
            }
        }
        .padding(12)
        .background(Color.asWindow)
        .clipShape(.rect(cornerRadius: 8))
    }
}
