// DesignSystemGlassControls — the appearance-aware control visuals of the S10.7 token contract:
// the carved slider (groove, knob, track) and the glass switch. Split out of
// `DesignSystemGlass.swift` (S10.8 B) so the surface/glow half keeps room under its length
// budget; like that file, this is a sanctioned definition file — the one other place the
// appearance may be read (semgrep `ui-no-appearance-branching`). No RGBA literal lives here
// either: every value is a Kit token.

import DesignTokenKit
import SwiftUI

// MARK: - Carved slider visuals (S10.7 PR 5 — the 8a track/knob recipe)

/// The 8a carved GROOVE (track): a token-filled base with a top inner shade (the inset
/// shadow) and a teal progress fill with a dark-only glow (grammar rule 6). Appearance-aware,
/// so it lives in this sanctioned file. Shared by the inspector `CarvedSlider` AND the footer
/// scrubber (PR 6) — one carved surface, two consumers. Vertically centered in whatever height
/// the caller frames it to; the knob/thumb is the caller's concern.
struct CarvedGroove: View {
    /// The teal-filled portion, as a fraction [0, 1] of the track width.
    let fillFraction: Double
    /// Track (groove) thickness.
    var height: CGFloat = .init(GlassDecor.carvedTrackHeight)
    /// The progress fill (S10.8 PR E: the realigned teal `meterFill` gradient by default —
    /// sliders, meters, and the playing scrubber share it; the scrubber's paused/
    /// interrupted states pass their solid state colors instead).
    var fillStyle: AnyShapeStyle = .init(DesignSystem.Gradient.meterFill)
    /// Whether the fill carries the dark-only teal glow (off when the fill isn't the accent
    /// family — e.g. the scrubber paused/interrupted — so a teal glow never sits under a
    /// grey fill).
    var glow: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    private static let innerShade: CGFloat = 2

    var body: some View {
        let dark = colorScheme == .dark
        GeometryReader { geo in
            let clamped = CGFloat(min(max(fillFraction, 0), 1))
            ZStack(alignment: .leading) {
                // Carved base: token fill + a top inner shade (the 8a inset shadow).
                Capsule()
                    .fill(SwiftUI.Color(token: GlassDecor.carvedTrack.value(for: dark ? .dark : .light)))
                    .overlay(alignment: .top) {
                        LinearGradient(
                            colors: [SwiftUI.Color(token: dark ? GlassDecor.carvedShadeDark
                                    : GlassDecor.carvedShadeLight), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: Self.innerShade)
                    }
                    .clipShape(Capsule())
                    .frame(height: height)

                Capsule()
                    .fill(fillStyle)
                    .frame(width: geo.size.width * clamped, height: height)
                    .shadow(color: (dark && glow) ? SwiftUI.Color(token: GlassDecor.sliderGlowDark) : .clear,
                            radius: 5)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

/// The 8a carved knob/thumb: a token-filled circle with a bottom inner shade (the physical
/// cue, both appearances) and, in light, a 1pt dark ring — the white knob's edge on the white
/// card (S10.8 B2a). Shared by the slider knob and the footer scrubber's hover thumb.
struct CarvedKnob: View {
    var size: CGFloat = .init(GlassDecor.sliderKnobSize)

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        Circle()
            .fill(SwiftUI.Color(token: GlassDecor.knobFill.value(for: dark ? .dark : .light)))
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, SwiftUI.Color(token: GlassDecor.knobShade)],
                               startPoint: .center, endPoint: .bottom)
                    .clipShape(Circle())
            }
            .overlay {
                if !dark {
                    Circle().strokeBorder(SwiftUI.Color(token: GlassDecor.knobRingLight), lineWidth: 1)
                }
            }
            .frame(width: size, height: size)
    }
}

/// The inspector slider's track+knob (S10.7 PR 5). Composes the shared `CarvedGroove` (fill to
/// the knob CENTER, so the teal meets the knob at every position) + a `CarvedKnob` at the
/// knob's inset travel position. `CarvedSlider` (UI/Controls) owns interaction.
struct CarvedTrack: View {
    /// Filled fraction in [0, 1].
    let fraction: Double

    private static let knobSize = CGFloat(GlassDecor.sliderKnobSize)

    var body: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - Self.knobSize, 0)
            let knobX = usable * CGFloat(min(max(fraction, 0), 1))
            // The teal reaches the knob's CENTER at every position (identical to the PR-5
            // fill width `knobX + knobSize/2`, expressed as a fraction of the track width).
            let fillFraction = Double((knobX + Self.knobSize / 2) / max(geo.size.width, 1))
            ZStack(alignment: .leading) {
                CarvedGroove(fillFraction: fillFraction)
                CarvedKnob()
                    .offset(x: knobX)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(height: Self.knobSize)
    }
}

// MARK: - Glass switch (S10.8 B2a — the Settings switches reuse it in F2)

/// The app's on/off switch: the native `.switch`, tinted per site with `accentFill` (plan §F). Light
/// edges the track with a 1pt dark hairline (grammar rule 2: the off track alone is ~1.09:1 on the
/// card) and shows DISABLED by the switch's own look plus a tertiary label, never a dim on top.
struct GlassSwitchStyle: ToggleStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let light = colorScheme != .dark
        let edge = SwiftUI.Color(token: GlassDecor.switchEdgeLight)
        // The native labeled switch's own layout (label, 8pt, switch; pixel-identical), re-composed
        // so the hairline sits on the track alone — the labels-hidden switch's frame IS its track.
        HStack(spacing: DesignSystem.Spacing.small) {
            configuration.label
                .foregroundStyle(light && !isEnabled ? DesignSystem.Color.labelTertiary : DesignSystem.Color.label)
                .accessibilityHidden(true) // the switch below carries the label
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(DesignSystem.Color.accentFill)
                .overlay { Capsule().strokeBorder(light ? edge : .clear, lineWidth: 1) }
        }
    }
}
