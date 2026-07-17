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

    /// Window base. Dark #1E1E1E pre-D10 (PR 2 re-bases toward the 8a deep base).
    public static let window = AppearancePair(
        light: .gray(0.93),
        dark: RGBAColor(red: 0.118, green: 0.118, blue: 0.118)
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

    public static let statusWarning = AppearancePair(both: RGBAColor(red: 1.0, green: 0.623, blue: 0.039)) // #FF9F0A
    /// NEW in S10.7 (PR 1a): the clipping/over-level red the loudness meters previously
    /// hand-painted as `Color.red` (design §3.1 disposition). Values are SwiftUI's palette
    /// red AS RESOLVED ON macOS 26 — #FF383C light / #FF4245 dark, exact fractions
    /// (empirically probed: `Color.red.resolve(in:)` ≡ `NSColor.systemRed`; the classic
    /// pre-26 #FF3B30/#FF453A is a visible hue shift — review BLOCKER-1). Pixel-invisible
    /// swap. The light value fails AA on light surfaces (pre-existing look) — PR-6 restyle.
    public static let statusError = AppearancePair(
        light: RGBAColor(red: 1.0, green: 56.0 / 255.0, blue: 60.0 / 255.0),
        dark: RGBAColor(red: 1.0, green: 66.0 / 255.0, blue: 69.0 / 255.0)
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

    // MARK: Registry (drives the invariant + audit tests — a token missing here is untested)

    /// Every pair above, by name. TOK tests iterate this; keep it in declaration order.
    public static let all: [(name: String, pair: AppearancePair)] = [
        ("window", window), ("card", card), ("panel", panel), ("hairline", hairline),
        ("label", label), ("labelSecondary", labelSecondary), ("labelTertiary", labelTertiary),
        ("labelDisabled", labelDisabled),
        ("accent", accent), ("accentDeep", accentDeep), ("onAccent", onAccent), ("blue", blue),
        ("statusWarning", statusWarning), ("statusError", statusError),
        ("rowNowPlaying", rowNowPlaying), ("rowSelected", rowSelected),
        ("iconFillTop", iconFillTop), ("iconFillMid", iconFillMid),
    ]
}

// MARK: - Slot widths (fixed-slot fit data — §7.1 SlotFitTests)

/// Fixed-width text slots whose widest legitimate string must fit (the S9 LUFS-truncation
/// class, asserted headlessly). Only slots under test live here; each new readout brings its
/// slot in the PR that adds it. The app-side `DesignSystem.Footer` re-exports these.
public enum SlotWidths {
    /// Footer scrubber time label ("88:88" is the widest mm:ss).
    public static let footerTimeLabel: Double = 46
}
