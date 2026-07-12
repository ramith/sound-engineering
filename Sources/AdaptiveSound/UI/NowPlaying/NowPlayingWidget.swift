import SwiftUI

// MARK: - Now Playing Widget

/// Compact card showing the current track's artwork placeholder, name, and live signal-path badge.
/// The progress/seek row now lives in the global footer transport (`NowPlayingBar`, L3).
struct NowPlayingWidget: View {
    @Environment(AudioViewModel.self) var viewModel

    var body: some View {
        if let selectedIndex = viewModel.selectedTrackIndex,
           selectedIndex < viewModel.playlist.count {
            let currentTrack = viewModel.playlist[selectedIndex]
            TrackCard(track: currentTrack)
        } else {
            EmptyTrackCard()
        }
    }
}

// MARK: - Track Card

private struct TrackCard: View {
    @Environment(AudioViewModel.self) private var viewModel
    let track: AudioFile

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

            SignalPathBadge(info: viewModel.signalPath)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        }
        .padding(12)
        .background(Color.asWindow)
        .clipShape(.rect(cornerRadius: 8))
    }
}

// MARK: - Signal Path Badge

/// Inline badge summarising the live signal path. Shows dot + formatted string
/// (or an interrupted warning). Private to this file — consumed only by `TrackCard`.
private struct SignalPathBadge: View {
    let info: SignalPathInfo

    var body: some View {
        HStack(spacing: 5) {
            if info.interrupted {
                interruptedContent
            } else {
                normalContent
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Signal path")
        .accessibilityValue(accessibilityValue)
    }

    // MARK: Interrupted state

    private var interruptedContent: some View {
        Group {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(DesignSystem.Color.statusWarning)
            Text("Device disconnected")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.asLabelSecond)
        }
    }

    // MARK: Normal state

    private var normalContent: some View {
        Group {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)

            badgeText
        }
    }

    // MARK: Dot color

    private var dotColor: Color {
        if info.fellBackToEnhanced || info.interrupted {
            return DesignSystem.Color.statusWarning
        }
        if info.path == .pure {
            return Color.asAccent
        }
        return Color.asLabelTertiary
    }

    // MARK: Badge text (path · rate · bits [· decoder])

    @ViewBuilder
    private var badgeText: some View {
        let segments = buildSegments()

        // Render interleaved segments with "·" separators in asLabelTertiary
        HStack(spacing: 2) {
            ForEach(Array(segments.enumerated()), id: \.offset) { idx, segment in
                if idx > 0 {
                    Text("·")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.asLabelTertiary)
                }
                Text(segment.text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(segment.color)
            }

            if info.fellBackToEnhanced {
                Text("·")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.asLabelTertiary)
                Text("(Pure unavailable)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.asLabelTertiary)
            }
        }
    }

    private struct BadgeSegment {
        let text: String
        let color: Color
    }

    private func buildSegments() -> [BadgeSegment] {
        var segments: [BadgeSegment] = []

        // 1. Path
        let pathText = info.path == .pure ? "Pure" : "Enhanced"
        segments.append(.init(text: pathText, color: Color.asLabelSecond))

        // 2. Sample rate — shared formatter in SignalPathInfo extension
        segments.append(.init(text: info.formattedRate, color: Color.asLabelSecond))

        // 3. Bit depth / format — only when informative
        if let bitsText = info.formattedBits {
            segments.append(.init(text: bitsText, color: Color.asLabelSecond))
        }

        // 4. Decoder — Pure path only
        if info.path == .pure, let dec = info.decoder {
            let decText = dec == .apple ? "Apple" : "FFmpeg"
            segments.append(.init(text: decText, color: Color.asLabelSecond))
        }

        // 5. Reimagine intensity — Enhanced path only, when > 0
        if info.path == .enhanced, info.intensityLinear > 0 {
            let pct = Int((info.intensityLinear * 100).rounded())
            segments.append(.init(text: "\(pct)%", color: Color.asLabelSecond))
        }

        // 6. Crossfeed badge — only when intensity > 0 (§9: don't show inaudible-chain badge)
        if info.intensityLinear > 0, let xfStrength = info.crossfeedStrength {
            segments.append(.init(text: "XF:\(xfStrength.displayName)", color: Color.asLabelSecond))
        }

        return segments
    }

    // MARK: Accessibility value

    private var accessibilityValue: String {
        if info.interrupted {
            return "Playback paused, output device disconnected"
        }

        let pathStr = info.path == .pure ? "Pure mode" : "Enhanced mode"
        let rateVal = info.achievedSampleRate > 0
            ? info.formattedRate.replacing(" kHz", with: " kilohertz")
            : "unknown rate"
        var parts = [pathStr, rateVal]

        if info.bitDepth > 0 {
            let kind = info.isFloat ? "float" : "integer"
            parts.append("\(info.bitDepth)-bit \(kind)")
        } else if info.isFloat {
            parts.append("32-bit float")
        }

        if info.path == .pure, let dec = info.decoder {
            parts.append(dec == .apple ? "Apple decoder" : "FFmpeg decoder")
        }

        var result = parts.joined(separator: ", ")
        if info.fellBackToEnhanced {
            result += " — Pure mode unavailable"
        }
        return result
    }
}
