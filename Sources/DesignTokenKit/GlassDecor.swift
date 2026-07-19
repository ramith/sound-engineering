// GlassDecor — the Regime-B edge-decoration data (S10.7 PR 3+, design §3.2): the strata a
// `.glassPanel` fill role composes (specular top rim, glass hairline, bottom light bleed,
// drop shadow) and the concentric radii. DATA ONLY — the app-side modifier composes it.
// Values are the 8a recipe's dark side; light values follow the §3.2 translation grammar
// (rim STAYS white but brighter; hairline FLIPS dark; bleed is DROPPED; shadows lighter and
// tighter — never an inversion).

import Foundation

public enum GlassDecor {
    // MARK: Radii (staged per consumer — TOK-01 asserts the concentric chain stays monotone)

    /// Inspector panel (8a: radius 22 — the outermost app panel).
    public static let panelRadius: Double = 22
    /// Analyzer lens (8a: radius 20; PR 3's first consumer).
    public static let lensRadius: Double = 20

    // MARK: Specular top rim (grammar rule 1: white on BOTH sides, brighter in light)

    public static let rim = AppearancePair(
        light: .gray(1.0, alpha: 0.55),
        dark: .gray(1.0, alpha: 0.17)
    )

    // MARK: Glass hairline (grammar rule 2: flips dark in light; FIRST token with real

    // Increase-Contrast variants — the §3.2 "stronger hairlines under IC" promise)

    public static let glassHairline = AppearancePair(
        light: .gray(0.0, alpha: 0.10),
        dark: .gray(1.0, alpha: 0.05),
        lightHighContrast: .gray(0.0, alpha: 0.30),
        darkHighContrast: .gray(1.0, alpha: 0.25)
    )

    // MARK: Bottom light bleed (grammar rule 3: DARK-ONLY — depth in light comes from shadow)

    public static let bleedDark: RGBAColor = .gray(1.0, alpha: 0.12)
    public static let bleedHeight: Double = 24

    // MARK: Carved sliders (PR 5 — 8a: 5pt inset tracks, 14pt knobs, dark-only teal glow)

    /// Knob diameter — in the Kit because the interaction math (pointer→fraction mapping
    /// over the knob's inset travel) and the visuals must share ONE value; a drift between
    /// them re-creates the mouse-down value-jump at the track extremes.
    public static let sliderKnobSize: Double = 14
    /// Carved groove (track) height — shared by the inspector sliders AND the footer scrubber
    /// (PR 6) so the two carved surfaces are visually identical. S10.8 PR E (realigned):
    /// slims 5 → 4 to the mock's slim-slider spec.
    public static let carvedTrackHeight: Double = 4
    /// Carved track base fill (the groove). S10.8 PR E: dark lifts 8% → 13% (the slimmer
    /// groove needs the stronger carve to stay visible on the denser panel).
    public static let carvedTrack = AppearancePair(
        light: .gray(0.0, alpha: 0.10),
        dark: .gray(1.0, alpha: 0.13)
    )
    /// The knob fill. White on BOTH sides for now — a pair (not a constant) because the
    /// PR-6 non-text-contrast pass owns the light-side value (white knob on the white-based
    /// light panel is a known open item).
    public static let knobFill = AppearancePair(both: .gray(1.0))
    /// The inset top shade inside the groove (8a `inset 0 1px 2px rgba(0,0,0,.4)`; light
    /// per grammar: much fainter).
    public static let carvedShadeDark: RGBAColor = .gray(0.0, alpha: 0.40)
    public static let carvedShadeLight: RGBAColor = .gray(0.0, alpha: 0.15)
    /// The teal fill's glow — DARK-ONLY (grammar rule 6), 8a `0 0 8-10px rgba(63,208,186,.45)`.
    public static let sliderGlowDark = RGBAColor(red: 63.0 / 255.0, green: 208.0 / 255.0,
                                                 blue: 186.0 / 255.0, alpha: 0.45)
    /// The knob's bottom inner shade (both appearances — it's a physical cue, not emission).
    public static let knobShade: RGBAColor = .gray(0.0, alpha: 0.25)

    // MARK: Capsule tab strip (S10.8 PR B — Realigned Target `png/01-toolbar.png`)

    /// The active tab capsule's teal glow — DARK-ONLY (grammar rule 6). Realigned spec:
    /// `asTealMid 50%, radius 8, y 1` (#1FA893 = the iconFill mid stop).
    public static let tabActiveGlowDark = RGBAColor(red: 31.0 / 255.0, green: 168.0 / 255.0,
                                                    blue: 147.0 / 255.0, alpha: 0.5)
    public static let tabActiveGlowRadius: Double = 8
    public static let tabActiveGlowOffsetY: Double = 1
    /// Track inner padding (track height = capsule + 2× this) and inter-tab spacing.
    public static let tabTrackPadding: Double = 3
    public static let tabSpacing: Double = 2
    /// Base active-capsule height (@ScaledMetric-scaled at the call site, realigned: 28pt).
    public static let tabCapsuleBaseHeight: Double = 28

    // MARK: Inspector floating card (S10.8 PR E — realigned `png/05`)

    /// The teal radial glow BEHIND/below the floating card (dark-only — grammar rule 6):
    /// `asTealMid 22% → clear`, blurred, extending past the card's bottom edge so the empty
    /// area under the hugged card reads intentional.
    public static let inspectorGlowDark = RGBAColor(red: 31.0 / 255.0, green: 168.0 / 255.0,
                                                    blue: 147.0 / 255.0, alpha: 0.22)
    public static let inspectorGlowBlur: Double = 18
    public static let inspectorGlowBleed: Double = 20
    public static let inspectorGlowRadius: Double = 200

    // MARK: Playing-row mini equalizer (S10.8 PR D — realigned `png/04`)

    // Deterministic sine bars (the Realigned Target SUPERSEDED the spectrum-driven plan —
    // recorded in s10-8-deviations-plan.md §B). Bars sit still at `eqBarMinScale` whenever
    // playback is paused or Reduce Motion is on (the §3.4 pulseIsActive predicate).
    public static let eqBarDurations: [Double] = [0.80, 1.05, 0.90]
    public static let eqBarPhases: [Double] = [0.0, 0.4, 0.7]
    public static let eqBarWidth: Double = 2.5
    public static let eqBarSpacing: Double = 1.5
    public static let eqBarContainerHeight: Double = 12
    public static let eqBarMinScale: Double = 0.34

    // MARK: Hero (PR 4 — 8a: teal title halo, dark-only per grammar rule 6; pulsing dot)

    /// The hero title's teal text-halo — DARK-ONLY (light drops emissive cues, grammar
    /// rule 6). A single constant, not a pair: the `.heroTitle()` modifier (the sanctioned
    /// appearance reader) applies it only in dark.
    public static let heroHaloDark = RGBAColor(red: 41.0 / 255.0, green: 182.0 / 255.0,
                                               blue: 164.0 / 255.0, alpha: 0.25)
    public static let heroHaloRadius: Double = 16
    public static let heroHaloOffsetY: Double = 2

    /// The ENHANCED badge's pulsing dot (8a: 1.6 s cycle, opacity 1 → 0.4) — the phase
    /// animator runs each half-cycle.
    public static let pulseHalfCycleSeconds: Double = 0.8
    public static let pulseDimOpacity: Double = 0.4
    /// Base badge capsule height (@ScaledMetric-scaled at the call site, 8a: 22pt).
    public static let badgeBaseHeight: Double = 22

    // MARK: Drop shadow (grammar rule 4: light = lighter AND tighter — tuned from the PR-3

    // founder screenshots: the first pass at literal half-of-dark (0.30 @ 18) read as a
    // gray smudge on the light window; native macOS light panels sit nearer 0.15)

    public static let shadowColor = AppearancePair(
        light: .gray(0.0, alpha: 0.15),
        dark: .gray(0.0, alpha: 0.60)
    )
    public static let shadowRadiusDark: Double = 36
    public static let shadowRadiusLight: Double = 12
    public static let shadowOffsetYDark: Double = 14
    public static let shadowOffsetYLight: Double = 5
}
