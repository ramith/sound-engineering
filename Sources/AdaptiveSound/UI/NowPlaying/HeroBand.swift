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

/// The §5 state mapping, as capsule badges. All colors/fills are tokens; the capsules are
/// `.glassPanel(.badge)` fills (Regime B — the resolver owns RT/IC).
private struct SignalBadgeRow: View {
    let info: SignalPathInfo
    let isPlaying: Bool
    let reduceMotion: Bool
    let badgeHeight: CGFloat

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            if info.interrupted {
                BadgeCapsule(height: badgeHeight) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.Color.statusWarning)
                    Text("Device disconnected")
                        .badgeText(DesignSystem.Color.label)
                }
            } else {
                pathBadge
                BadgeCapsule(height: badgeHeight) {
                    Text(info.formattedRate).badgeText(DesignSystem.Color.label)
                }
                // No bits/decoder capsules: relocated to the inspector's signal-detail
                // line (§5) — the hero-left's 300pt minimum budget (LAY-01) assumes the
                // SHORT badge set.
                if info.path == .enhanced, info.intensityLinear > 0 {
                    BadgeCapsule(height: badgeHeight) {
                        Text("\(Int((info.intensityLinear * 100).rounded())) %")
                            .badgeText(DesignSystem.Color.label)
                    }
                }
                if info.intensityLinear > 0, let strength = info.crossfeedStrength {
                    BadgeCapsule(height: badgeHeight) {
                        Text("XF:\(strength.displayName)")
                            .badgeText(DesignSystem.Color.label)
                    }
                }
                if info.fellBackToEnhanced {
                    BadgeCapsule(height: badgeHeight) {
                        Text("Pure unavailable")
                            .badgeText(DesignSystem.Color.statusWarning)
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

    /// PURE (accent dot, monochrome text) vs ENHANCED (pulsing dot — §3.4 pattern).
    private var pathBadge: some View {
        BadgeCapsule(height: badgeHeight) {
            let pure = info.path == .pure
            let dotColor = pure ? DesignSystem.Color.accent
                : (info.fellBackToEnhanced ? DesignSystem.Color.statusWarning
                    : DesignSystem.Color.labelTertiary)
            let dot = Circle().fill(dotColor).frame(width: 5, height: 5)
            if !pure, pulseIsActive(isPlaying: isPlaying, reduceMotion: reduceMotion) {
                // Conditional phaseAnimator (§3.4): unmounting it IS the deterministic stop;
                // the banned .repeatForever+onAppear idiom zombie-animates after gating flips.
                dot.phaseAnimator([1.0, GlassDecor.pulseDimOpacity]) { view, opacity in
                    view.opacity(opacity)
                } animation: { _ in
                    .easeInOut(duration: GlassDecor.pulseHalfCycleSeconds)
                }
            } else {
                dot
            }
            Text(pure ? "PURE" : "ENHANCED")
                .badgeText(DesignSystem.Color.label)
                .tracking(0.5)
        }
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
