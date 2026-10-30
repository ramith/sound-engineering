import DesignTokenKit
import SwiftUI

// MARK: - The hero's signal chips (one level of the badge row)

/// How much the badge row says in words (`SignalBadgeRow` shows the first level that fits the hero): everything;
/// then why Pure isn't playing bit-perfect (`PureModeReason`) by the amber warning glyph alone; then also the format
/// chip by its rate alone. What a level leaves out is on the chip's tooltip, and the row's VoiceOver value says the
/// reason in words at every level.
enum SignalBadgeLevel: CaseIterable {
    /// Every chip in words: "FLAC · 48 kHz", "Pure off: Bluetooth".
    case full
    /// Pure's reason as its glyph.
    case reasonGlyph
    /// Pure's reason as its glyph, and the format chip's rate without the format ("48 kHz").
    case rateOnly
}

/// The badge row's chips at one `level`: the path (PURE, or the teal ENHANCED with its dot), the format and rate,
/// the fold, the crossfeed that plays, and why Pure isn't playing bit-perfect; or the interrupted state alone.
struct SignalBadges: View {
    let info: SignalPathInfo
    /// Master Gain, for the sentence when Pure waits for it.
    let masterGain: Float
    /// The current track's file format ("MP3", "FLAC") — nil hides the segment.
    let format: String?
    /// The ENHANCED dot pulses: playing, and Reduce Motion off.
    let pulses: Bool
    let badgeHeight: CGFloat
    let level: SignalBadgeLevel

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            if info.interrupted {
                BadgeCapsule(height: badgeHeight) {
                    warningGlyph
                    Text("Device disconnected")
                        .badgeText(DesignSystem.Color.label)
                }
            } else {
                pathBadge
                formatRateBadge
                // The fold (R1.1-B, US-R1F-08 item 6): "5.1 → stereo", and "· measuring" on the first play of a
                // surround track nobody has measured yet. When Pure was asked for and declined for the channels, the
                // badge IS that reason — its sentence on hover, the dot amber — so the row never carries both.
                if let fold = info.foldBadge {
                    BadgeCapsule(height: badgeHeight) {
                        Text(fold)
                            .badgeText(DesignSystem.Color.label)
                            .lineLimit(1)
                    }
                    .fixedSize()
                    .help(foldHelp)
                }
                // No bits/decoder capsules: relocated to the inspector's signal-detail
                // line (§5) — the hero-left's 300pt minimum budget (LAY-01) assumes the
                // SHORT badge set.
                if let strength = info.audibleCrossfeed {
                    BadgeCapsule(height: badgeHeight) {
                        Text("XF:\(strength.displayName)")
                            .badgeText(DesignSystem.Color.label)
                    }
                }
                // Why Pure isn't playing bit-perfect (C-34): a short note, or its glyph where the row is too full;
                // its sentence on hover either way.
                if let reason = info.pureReason, !foldCarries(reason) {
                    BadgeCapsule(height: badgeHeight) {
                        if level == .full {
                            Text(reason.note)
                                .badgeText(DesignSystem.Color.statusWarningText)
                                .lineLimit(1)
                        } else {
                            warningGlyph
                        }
                    }
                    .help(reason.detail(in: info, masterGain: masterGain))
                }
            }
        }
    }

    /// The amber warning triangle: the interrupted chip's, and Pure's reason where its words don't fit.
    private var warningGlyph: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
            .foregroundStyle(DesignSystem.Color.statusWarningText)
    }

    /// Whether the fold badge already says `reason`: Pure declined a file with more channels than the output.
    private func foldCarries(_ reason: PureModeReason) -> Bool {
        reason == .channelCountMismatch && info.foldBadge != nil
    }

    /// The fold badge's tooltip: Pure's reason when Pure was asked for, else what the fold does.
    private var foldHelp: String {
        if let reason = info.pureReason, foldCarries(reason) {
            return reason.detail(in: info, masterGain: masterGain)
        }
        let measuring = info.foldBadge?.hasSuffix("measuring") == true
        return "This track has more channels than your output, so Enhanced folds it to stereo"
            + (measuring ? ". It plays quieter until it is measured." : ".")
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
        if pulses {
            dot.phaseAnimator([1.0, GlassDecor.pulseDimOpacity]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: GlassDecor.pulseHalfCycleSeconds)
            }
        } else {
            dot
        }
    }

    /// `MP3 · 48 kHz` — the grey mono chip; `48 kHz` at the tightest level, the format on its
    /// tooltip. Text stays the PRIMARY label (not the mock's white-60%): R4-BADGE-01's standing
    /// rule — dimmed hierarchy on a badge over the teal glow core fails AA; hierarchy on a chip
    /// comes from the capsule, not dimmed text.
    private var formatRateBadge: some View {
        let shownFormat = level == .rateOnly ? nil : format
        return BadgeCapsule(height: badgeHeight) {
            Text([shownFormat, info.formattedRate].compactMap(\.self).joined(separator: " · "))
                .font(DesignSystem.Font.monoSmall.weight(.semibold))
                .foregroundStyle(DesignSystem.Color.label)
        }
        .help(level == .rateOnly ? format ?? "" : "")
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
        font(DesignSystem.Font.micro).foregroundStyle(color)
    }
}
