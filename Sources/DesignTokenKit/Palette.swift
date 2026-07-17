// Palette — the single source for every color the app paints (S10.7 single-source
// invariant, design §3.2): `DesignSystem.Color.*` re-exports THESE values; the R4 contrast
// audit composites THESE values. A color that exists here and (differently) in the app is
// the "hand-mirror drift" failure the invariant exists to prevent.
//
// Values are byte-identical to the pre-S10.7 `DesignSystem.swift` literals (PR 1a is a
// zero-visual-change refactor); the D10 deep-base re-tune arrives in PR 2 by EDITING these.

import Foundation

// MARK: - Palette

public enum Palette {
    // MARK: Surfaces (elevation stack)

    /// Window base. Dark = the 8a DEEP base #0e1013 (D10, PR 2 — the release look: every 8a
    /// glow/fill/rim value is tuned against this; the pre-D10 #1E1E1E washed them out).
    /// Light untouched (the light grammar re-derives, never inverts — design §3.2).
    public static let window = AppearancePair(
        light: .gray(0.93),
        dark: RGBAColor(red: 14.0 / 255.0, green: 16.0 / 255.0, blue: 19.0 / 255.0)
    )
    public static let card = AppearancePair(light: .gray(1.0), dark: .gray(1.0, alpha: 0.045))
    public static let panel = AppearancePair(light: .gray(1.0), dark: .gray(1.0, alpha: 0.06))
    public static let hairline = AppearancePair(
        light: .gray(0.0, alpha: 0.12),
        dark: .gray(1.0, alpha: 0.08)
    )

    // MARK: Labels (WCAG-audited hierarchy — see ContrastAuditTests)

    public static let label = AppearancePair(light: .gray(0.0, alpha: 0.90), dark: .gray(1.0, alpha: 0.92))
    public static let labelSecondary = AppearancePair(
        light: .gray(0.0, alpha: 0.62),
        dark: .gray(1.0, alpha: 0.55)
    )
    public static let labelTertiary = AppearancePair(
        light: .gray(0.0, alpha: 0.55),
        dark: .gray(1.0, alpha: 0.48)
    )
    /// WCAG-exempt (disabled text).
    public static let labelDisabled = AppearancePair(
        light: .gray(0.0, alpha: 0.28),
        dark: .gray(1.0, alpha: 0.25)
    )

    // MARK: Accent family (appearance-independent — the teal reads on both)

    public static let accent = AppearancePair(both: RGBAColor(red: 0.161, green: 0.714, blue: 0.643)) // #29B6A4
    public static let accentDeep = AppearancePair(both: RGBAColor(red: 0.078, green: 0.537, blue: 0.478)) // #148979
    /// Foreground ON the accent (play glyph over teal). Known ≈2.5:1 — pre-existing,
    /// flagged to the founder (design §7 R4 scope guard), not gated here.
    public static let onAccent = AppearancePair(both: .gray(1.0))
    /// Alternate accent (swap-in blue).
    public static let blue = AppearancePair(both: RGBAColor(red: 0.039, green: 0.518, blue: 1.0)) // #0A84FF

    // MARK: Status

    //
    // S10.7 PR 6 (founder decision — "split text vs fill"): the vivid `status*` tokens are the
    // FILL/indicator colors (meter hot-bar, status dots — non-text, WCAG 3:1); a `status*Text`
    // variant carries the darker, AA-legible shade for TEXT/glyph sites (4.5:1). On DARK the
    // vivid value already clears text AA (R4-LEG-03 dark / R4-BADGE-01 dark), so the text
    // variant differs only in LIGHT — where vivid orange/red on near-white is illegible.

    public static let statusWarning = AppearancePair(both: RGBAColor(red: 1.0, green: 0.623, blue: 0.039)) // #FF9F0A
    /// NEW in S10.7 (PR 1a): the clipping/over-level red the loudness meters previously
    /// hand-painted as `Color.red` (design §3.1 disposition). Values are SwiftUI's palette
    /// red AS RESOLVED ON macOS 26 — #FF383C light / #FF4245 dark, exact fractions
    /// (empirically probed: `Color.red.resolve(in:)` ≡ `NSColor.systemRed`; the classic
    /// pre-26 #FF3B30/#FF453A is a visible hue shift — review BLOCKER-1). This is the FILL
    /// value (meter hot-bar, non-text 3:1); text sites use `statusErrorText`.
    public static let statusError = AppearancePair(
        light: RGBAColor(red: 1.0, green: 56.0 / 255.0, blue: 60.0 / 255.0),
        dark: RGBAColor(red: 1.0, green: 66.0 / 255.0, blue: 69.0 / 255.0)
    )
    /// The TEXT/glyph variant of the error red (PR 6, D-split). Light = a dark red that clears
    /// AA text on the darkest audited light surface (window ≈ 0.848 L); dark = the vivid value
    /// (already AA on the deep base). #A3000F light.
    public static let statusErrorText = AppearancePair(
        light: RGBAColor(red: 163.0 / 255.0, green: 0.0, blue: 15.0 / 255.0),
        dark: RGBAColor(red: 1.0, green: 66.0 / 255.0, blue: 69.0 / 255.0)
    )
    /// The TEXT/glyph variant of the warning orange (PR 6, D-split). Light = a dark amber that
    /// clears AA text on the light badge fill (≈ 0.737 L, the worst warning-text backdrop);
    /// dark = the vivid orange (already AA there). #6E4400 light.
    public static let statusWarningText = AppearancePair(
        light: RGBAColor(red: 110.0 / 255.0, green: 68.0 / 255.0, blue: 0.0),
        dark: RGBAColor(red: 1.0, green: 0.623, blue: 0.039)
    )

    // MARK: Row tints (derived from accent — appearance-independent)

    public static let rowNowPlaying = AppearancePair(both: accent.light.opacity(0.25))
    public static let rowSelected = AppearancePair(both: accent.light.opacity(0.12))

    // MARK: Icon-fill gradient stops (app-mark squircle / play button — appearance-independent)

    /// The two upper stops of `DesignSystem.Gradient.iconFill` (#3FD0BA, #1FA893 as the
    /// shipped rounded doubles — byte-identity to the pre-Kit literals beats hex purity);
    /// the third stop is `accentDeep`.
    public static let iconFillTop = AppearancePair(both: RGBAColor(red: 0.247, green: 0.816, blue: 0.729))
    public static let iconFillMid = AppearancePair(both: RGBAColor(red: 0.122, green: 0.659, blue: 0.576))

    // MARK: Glass-look fills (Regime B — design §3.1; staged per consumer)

    /// The analyzer lens fill (8a: `rgba(16,18,21,.42)` — a darker inset against the glowed
    /// field). Light per the §3.2 grammar: white-based glass. Under Reduce Transparency /
    /// Increase Contrast the resolver serves the OPAQUE composite (fill over window),
    /// derived — never a third hand-kept value.
    public static let lensFill = AppearancePair(
        light: .gray(1.0, alpha: 0.55),
        dark: RGBAColor(red: 16.0 / 255.0, green: 18.0 / 255.0, blue: 21.0 / 255.0, alpha: 0.42)
    )

    /// Hero badge capsules (8a "small controls": white 7–9% fills). Light per the grammar:
    /// a faint dark wash + the glass hairline carries the edge. RT/IC → opaque composite,
    /// derived by the resolver like every fill role.
    public static let badgeFill = AppearancePair(
        light: .gray(0.0, alpha: 0.06),
        dark: .gray(1.0, alpha: 0.08)
    )

    /// The inspector panel fill (8a: `rgba(30,33,38,.5)`). Light per the grammar: white-based
    /// glass, one notch stronger than the lens so the column reads as the room's wall, not a
    /// second lens. Same derived RT/IC-opaque contract.
    public static let panelFill = AppearancePair(
        light: .gray(1.0, alpha: 0.60),
        dark: RGBAColor(red: 30.0 / 255.0, green: 33.0 / 255.0, blue: 38.0 / 255.0, alpha: 0.5)
    )

    // MARK: Ambient glow field (S10.7 PR 2 — design §3.3)

    /// The three 8a content glows. Dark alphas are the 8a spec (.28/.12/.10 over the deep
    /// base); light alphas follow the §3.2 grammar rule 5 (~1/3 — ambience, not smears).
    /// D8 pre-binding: when art-sampling lands (PR 7), sampled colors CLAMP into ranges
    /// derived from these tokens, so the R4 audit keeps enumerating bounded worst cases.
    public static let glowTeal = AppearancePair(
        light: RGBAColor(red: 41.0 / 255.0, green: 182.0 / 255.0, blue: 164.0 / 255.0, alpha: 0.09),
        dark: RGBAColor(red: 41.0 / 255.0, green: 182.0 / 255.0, blue: 164.0 / 255.0, alpha: 0.28)
    )
    public static let glowLime = AppearancePair(
        light: RGBAColor(red: 200.0 / 255.0, green: 240.0 / 255.0, blue: 106.0 / 255.0, alpha: 0.04),
        dark: RGBAColor(red: 200.0 / 255.0, green: 240.0 / 255.0, blue: 106.0 / 255.0, alpha: 0.12)
    )
    public static let glowBlue = AppearancePair(
        light: RGBAColor(red: 79.0 / 255.0, green: 178.0 / 255.0, blue: 214.0 / 255.0, alpha: 0.033),
        dark: RGBAColor(red: 79.0 / 255.0, green: 178.0 / 255.0, blue: 214.0 / 255.0, alpha: 0.10)
    )

    // MARK: Registry (drives the invariant + audit tests — a token missing here is untested)

    /// Every pair above, by name. TOK tests iterate this; keep it in declaration order.
    public static let all: [(name: String, pair: AppearancePair)] = [
        ("window", window), ("card", card), ("panel", panel), ("hairline", hairline),
        ("label", label), ("labelSecondary", labelSecondary), ("labelTertiary", labelTertiary),
        ("labelDisabled", labelDisabled),
        ("accent", accent), ("accentDeep", accentDeep), ("onAccent", onAccent), ("blue", blue),
        ("statusWarning", statusWarning), ("statusError", statusError),
        ("statusWarningText", statusWarningText), ("statusErrorText", statusErrorText),
        ("rowNowPlaying", rowNowPlaying), ("rowSelected", rowSelected),
        ("iconFillTop", iconFillTop), ("iconFillMid", iconFillMid),
        ("glowTeal", glowTeal), ("glowLime", glowLime), ("glowBlue", glowBlue),
        ("lensFill", lensFill), ("badgeFill", badgeFill), ("panelFill", panelFill),
        ("glassRim", GlassDecor.rim), ("glassHairline", GlassDecor.glassHairline),
        ("glassShadow", GlassDecor.shadowColor),
        ("carvedTrack", GlassDecor.carvedTrack), ("knobFill", GlassDecor.knobFill),
    ]
}

// MARK: - Slot widths (fixed-slot fit data — §7.1 SlotFitTests)

/// Fixed-width text slots whose widest legitimate string must fit (the S9 LUFS-truncation
/// class, asserted headlessly). Only slots under test live here; each new readout brings its
/// slot in the PR that adds it. The app-side `DesignSystem.Footer` re-exports these.
public enum SlotWidths {
    /// Footer scrubber time label ("88:88" is the widest mm:ss).
    public static let footerTimeLabel: Double = 46
    /// The chrome device-pill sample-rate readout (D5). Widest legitimate string is a
    /// high-res fractional rate — "176.4 kHz" (9 chars); SLOT-02 asserts it fits.
    public static let chromeSampleRate: Double = 66
}
