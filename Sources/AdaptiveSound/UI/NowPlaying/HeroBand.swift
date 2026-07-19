import DesignTokenKit
import SwiftUI

// MARK: - Hero Band (S10.7 PR 4 — design §5)

/// The Now Playing hero: the 8a 28/800 title (dark-only teal halo), artist line, and the
/// signal-path BADGE ROW — the full state mapping the retired `NowPlayingWidget` carried
/// (design §5): `PURE` (monochrome) / `ENHANCED` + pulsing dot / the "(Pure unavailable)"
/// fallback warning / the interrupted state — plus rate/intensity/crossfeed capsules.
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
                Text(nowPlaying.currentArtist ?? "Unknown Artist")
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
/// The extra STATES stay: PURE keeps its monochrome chip, crossfeed and the Pure-fallback
/// warning keep theirs, interrupted replaces the row. All colors/fills are audited tokens.
private struct SignalBadgeRow: View {
    let info: SignalPathInfo
    /// The current track's file format ("MP3", "FLAC") — nil hides the segment.
    let format: String?
    let isPlaying: Bool
    let reduceMotion: Bool
    let badgeHeight: CGFloat

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            if info.interrupted {
                BadgeCapsule(height: badgeHeight) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.Color.statusWarningText)
                    Text("Device disconnected")
                        .badgeText(DesignSystem.Color.label)
                }
            } else {
                pathBadge
                formatRateBadge
                // No bits/decoder capsules: relocated to the inspector's signal-detail
                // line (§5) — the hero-left's 300pt minimum budget (LAY-01) assumes the
                // SHORT badge set.
                if info.intensityLinear > 0, let strength = info.crossfeedStrength {
                    BadgeCapsule(height: badgeHeight) {
                        Text("XF:\(strength.displayName)")
                            .badgeText(DesignSystem.Color.label)
                    }
                }
                if info.fellBackToEnhanced {
                    BadgeCapsule(height: badgeHeight) {
                        Text("Pure unavailable")
                            .badgeText(DesignSystem.Color.statusWarningText)
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: info.path)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: info.interrupted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Signal path")
        .accessibilityValue(SignalPathAccessibility.value(for: info))
    }

    /// PURE (accent dot, monochrome chip — untouched by the realign) vs ENHANCED: the
    /// realigned TEAL chip carrying the pulsing dot + the live intensity in one string.
    @ViewBuilder private var pathBadge: some View {
        if info.path == .pure {
            BadgeCapsule(height: badgeHeight) {
                Circle().fill(DesignSystem.Color.accent).frame(width: 5, height: 5)
                Text("PURE")
                    .badgeText(DesignSystem.Color.label)
                    .tracking(0.5)
            }
        } else {
            TealBadgeCapsule(height: badgeHeight) {
                pulsingDot
                Text(enhancedText)
                    .badgeText(DesignSystem.Color.accentText)
                    .tracking(0.5)
            }
        }
    }

    /// One string, live values (realigned): `ENHANCED · 20%`; plain `ENHANCED` at 0%
    /// (bit-perfect blend — a zero reads as noise, not information).
    private var enhancedText: String {
        let percent = Int((info.intensityLinear * 100).rounded())
        return percent > 0 ? "ENHANCED · \(percent)%" : "ENHANCED"
    }

    /// The 6pt dot: pulses via the §3.4 conditional phaseAnimator (unmounting IS the
    /// deterministic stop); frozen at full opacity when paused or under Reduce Motion.
    /// Amber when Pure fell back (the warning chip beside it carries the words).
    @ViewBuilder private var pulsingDot: some View {
        let dot = Circle()
            .fill(info.fellBackToEnhanced ? DesignSystem.Color.statusWarning
                : DesignSystem.Color.accentBright)
            .frame(width: 6, height: 6)
        if pulseIsActive(isPlaying: isPlaying, reduceMotion: reduceMotion) {
            dot.phaseAnimator([1.0, GlassDecor.pulseDimOpacity]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: GlassDecor.pulseHalfCycleSeconds)
            }
        } else {
            dot
        }
    }

    /// `MP3 · 48 kHz` — the grey mono chip. Text stays the PRIMARY label (not the mock's
    /// white-60%): R4-BADGE-01's standing rule — dimmed hierarchy on a badge over the teal
    /// glow core fails AA; hierarchy on a chip comes from the capsule, not dimmed text.
    private var formatRateBadge: some View {
        BadgeCapsule(height: badgeHeight) {
            Text([format, info.formattedRate].compactMap(\.self).joined(separator: " · "))
                .font(DesignSystem.Font.monoSmall.weight(.semibold))
                .foregroundColor(DesignSystem.Color.label)
        }
    }
}

// MARK: - Teal badge capsule (the realigned ENHANCED chip)

/// The accent-tinted chip: the audited `controlActiveFill` + accent ring pair (same family
/// as the queue header's toggled-on chips; text/glyphs on it are `accentText`, R4-CHIP-02).
private struct TealBadgeCapsule<Content: View>: View {
    let height: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 5) { content }
            .padding(.horizontal, 11)
            .frame(height: height)
            .background(Capsule().fill(DesignSystem.Color.controlActiveFill))
            .overlay(Capsule().strokeBorder(DesignSystem.Color.accent.opacity(0.28), lineWidth: 1))
    }
}

// MARK: - Badge capsule

private struct BadgeCapsule<Content: View>: View {
    let height: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        // Fill + rim + hairline all come from the `.badge` role's strata — no site paint.
        HStack(spacing: 5) { content }
            .padding(.horizontal, 10)
            .frame(height: height)
            .glassPanel(.badge, in: Capsule())
    }
}

private extension Text {
    func badgeText(_ color: SwiftUI.Color) -> Text {
        font(DesignSystem.Font.micro).foregroundColor(color)
    }
}

// MARK: - Accessibility value (carried over from the retired SignalPathBadge)

enum SignalPathAccessibility {
    static func value(for info: SignalPathInfo) -> String {
        if info.interrupted { return "Playback paused, output device disconnected" }
        let pathText = info.path == .pure ? "Pure mode" : "Enhanced mode"
        let rateText = info.achievedSampleRate > 0
            ? info.formattedRate.replacing(" kHz", with: " kilohertz")
            : "unknown rate"
        var parts = [pathText, rateText]
        if info.bitDepth > 0 {
            parts.append("\(info.bitDepth)-bit \(info.isFloat ? "float" : "integer")")
        } else if info.isFloat {
            parts.append("32-bit float")
        }
        if info.path == .pure, let decoder = info.decoder {
            parts.append(decoder == .apple ? "Apple decoder" : "FFmpeg decoder")
        }
        var result = parts.joined(separator: ", ")
        if info.fellBackToEnhanced { result += " — Pure mode unavailable" }
        return result
    }
}
