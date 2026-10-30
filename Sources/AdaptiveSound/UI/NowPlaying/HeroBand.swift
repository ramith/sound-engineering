import DesignTokenKit
import LibraryStore
import SwiftUI

// MARK: - Hero Band (S10.7 PR 4 — design §5)

/// The Now Playing hero: the 8a 28/800 title (dark-only teal halo), artist line, and the
/// signal-path BADGE ROW — the full state mapping the retired `NowPlayingWidget` carried
/// (design §5): `PURE` (monochrome) / `ENHANCED` + pulsing dot / why Pure isn't playing
/// bit-perfect, in a few words (`PureModeReason.note`, R1.1-A) / the interrupted state — plus
/// rate/intensity/crossfeed capsules.
/// Decoder/bits live in the inspector's signal-detail line (PR 5 relocation, §5); the
/// SPOKEN summary here deliberately keeps them — one VoiceOver stop for the whole path.
///
/// First-launch/empty state is DESIGNED, not endured (§5): placeholder title in
/// `labelSecondary`, NO halo, the badge row hidden-but-space-reserved so nothing reflows on
/// first play. Track changes crossfade (Reduce-Motion-gated); the pulse follows the §3.4
/// mandated conditional-phaseAnimator pattern (never `.repeatForever` + `onAppear`).
struct HeroBand: View {
    @Environment(AudioViewModel.self) private var viewModel
    @Environment(NowPlayingController.self) private var nowPlaying
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 8a: badges are capsule-height-consistent at 22pt — scaled with Dynamic Type so the
    /// row never clips (`@ScaledMetric`, review m9; a literal 22 clips at large text sizes).
    @ScaledMetric(relativeTo: .subheadline) private var badgeHeight = CGFloat(GlassDecor.badgeBaseHeight)

    private var currentTrack: AudioFile? {
        guard let index = viewModel.selectedTrackIndex,
              index < viewModel.playlist.count else { return nil }
        return viewModel.playlist[index]
    }

    var body: some View {
        let track = currentTrack
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            if let track {
                Text(track.name)
                    .heroTitle()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(track.name) // long-title tooltip (§5)
                    .contentTransition(.opacity)
                Text(nowPlaying.currentArtist ?? unknownArtistName)
                    .font(DesignSystem.Font.body)
                    .foregroundStyle(DesignSystem.Color.labelSecondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            } else {
                // Empty state (§5): quiet placeholder, NO halo, same line metrics.
                Text("Nothing playing")
                    .font(DesignSystem.Font.heroTitle)
                    .foregroundStyle(DesignSystem.Color.labelSecondary)
                    .lineLimit(1)
                Text("Click a track to play")
                    .font(DesignSystem.Font.body)
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
                    .lineLimit(1)
            }

            // The badge row reserves its space even when hidden (empty state) so first
            // play never reflows the hero (§5).
            SignalBadgeRow(info: viewModel.signalPath,
                           masterGain: viewModel.masterGain,
                           format: track?.format,
                           isPlaying: viewModel.isPlaying,
                           reduceMotion: reduceMotion,
                           badgeHeight: badgeHeight)
                .opacity(track == nil ? 0 : 1)
                .accessibilityHidden(track == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: track?.id)
    }
}

// MARK: - Signal badge row

/// The §5 state mapping, realigned to EXACTLY TWO core chips (S10.8 PR F — `png/02`):
/// the teal path chip (`● ENHANCED · 20%` — dot + path + live intensity in ONE string) and
/// the grey format·rate chip (`MP3 · 48 kHz` — the format segment is NEW to the hero).
/// The extra STATES stay: PURE keeps its monochrome chip, the fold, crossfeed and the
/// Pure-fallback warning keep theirs, interrupted replaces the row (`SignalBadges`). All
/// colors/fills are audited tokens.
///
/// The row holds by STRUCTURE, never squeezed (R1.1-B, review-ui M2): where its chips don't fit
/// the hero's text column — half of what the lens leaves, 414 pt at the 880 pt window and 474 at
/// 1000, against about 525 for a folded surround file with Pure declined for Bluetooth — Pure's
/// reason gives way to its glyph, then the format chip to its rate (`SignalBadgeLevel`), each on
/// its tooltip. The row is one VoiceOver element whose value says the reason in words throughout.
struct SignalBadgeRow: View {
    let info: SignalPathInfo
    /// Master Gain, for the sentence when Pure waits for it.
    let masterGain: Float
    /// The current track's file format ("MP3", "FLAC") — nil hides the segment.
    let format: String?
    let isPlaying: Bool
    let reduceMotion: Bool
    let badgeHeight: CGFloat

    var body: some View {
        ViewThatFits(in: .horizontal) {
            badges(.full)
            badges(.reasonGlyph)
            badges(.rateOnly)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: info.path)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: info.interrupted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Signal path")
        .accessibilityValue(SignalPathAccessibility.value(for: info))
    }

    /// The row's chips at `level`.
    func badges(_ level: SignalBadgeLevel) -> SignalBadges {
        SignalBadges(info: info, masterGain: masterGain, format: format,
                     pulses: pulseIsActive(isPlaying: isPlaying, reduceMotion: reduceMotion),
                     badgeHeight: badgeHeight, level: level)
    }
}

// MARK: - Accessibility value (carried over from the retired SignalPathBadge)

enum SignalPathAccessibility {
    static func value(for info: SignalPathInfo) -> String {
        if info.interrupted {
            return "Playback paused, output device disconnected"
        }
        let pathText = info.path == .pure ? "Pure mode" : "Enhanced mode"
        let rateText = info.achievedSampleRate > 0 ? info.spokenRate : "unknown rate"
        var parts = [pathText, rateText]
        if info.bitDepth > 0 {
            parts.append("\(info.bitDepth)-bit \(info.isFloat ? "float" : "integer")")
        } else if info.isFloat {
            parts.append("32-bit float")
        }
        if info.path == .pure, let decoder = info.decoder {
            parts.append(decoder == .apple ? "Apple decoder" : "FFmpeg decoder")
        }
        if let fold = info.spokenFoldBadge {
            parts.append(fold)
        }
        if let strength = info.audibleCrossfeed {
            parts.append("crossfeed \(strength.displayName)")
        }
        var result = parts.joined(separator: ", ")
        if let reason = info.pureReason {
            result += " — " + reason.note
        }
        return result
    }
}
