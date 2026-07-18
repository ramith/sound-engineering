// DesignTokenKit — the app's design-token DATA and their pure resolvers (S10.7 R0).
//
// Admission charter (s10-7-liquid-glass-design.md §3.2): token data (color pairs, radii,
// decoration constants, slot widths) and PURE resolvers over appearance, accessibility flags,
// and time. NOTHING here may import SwiftUI/AppKit (a strict-gate purity guard enforces it) —
// that is what makes every claim about the visual system a headless, forever-green test
// instead of an eyeball. The app-side `DesignSystemGlass.swift` bridges this data into
// SwiftUI values; no RGBA value may exist both here and there (single-source invariant).

import Foundation

// MARK: - RGBA color (plain data)

/// A straight-alpha sRGB color. Components are in [0, 1]; `alpha` < 1 marks a translucent
/// token (composited by `over(_:)` exactly the way the audit needs).
public struct RGBAColor: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Grayscale convenience — `white` is the gray level.
    public static func gray(_ white: Double, alpha: Double = 1.0) -> RGBAColor {
        RGBAColor(red: white, green: white, blue: white, alpha: alpha)
    }

    /// A copy with a different alpha (token derivations like the accent row tints).
    public func opacity(_ alpha: Double) -> RGBAColor {
        RGBAColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

// MARK: - Compositing + WCAG math (pure; the R4 audit's engine)

public extension RGBAColor {
    /// Straight-alpha "source over" compositing in sRGB space (the standard audit
    /// approximation: blending happens in gamma space, matching what AppKit does for
    /// plain translucent fills). Result is opaque when the backdrop is opaque.
    func over(_ backdrop: RGBAColor) -> RGBAColor {
        let outAlpha = alpha + backdrop.alpha * (1 - alpha)
        guard outAlpha > 0 else { return RGBAColor(red: 0, green: 0, blue: 0, alpha: 0) }
        func channel(_ fg: Double, _ bg: Double) -> Double {
            (fg * alpha + bg * backdrop.alpha * (1 - alpha)) / outAlpha
        }
        return RGBAColor(red: channel(red, backdrop.red),
                         green: channel(green, backdrop.green),
                         blue: channel(blue, backdrop.blue),
                         alpha: outAlpha)
    }

    /// WCAG 2.x relative luminance (sRGB linearization). Defined for opaque colors;
    /// composite translucent tokens onto their backdrop first.
    var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio between two OPAQUE colors (≥ 4.5 = AA text, ≥ 3.0 = non-text).
    static func contrastRatio(_ first: RGBAColor, _ second: RGBAColor) -> Double {
        let lighter = max(first.relativeLuminance, second.relativeLuminance)
        let darker = min(first.relativeLuminance, second.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

// MARK: - Appearance pair

/// One token = one light value + one dark value (S9-T posture: appearance is owned by the
/// token layer, never by views). Increased-contrast variants default to the base values so
/// tokens gain them incrementally without touching call sites.
public struct AppearancePair: Sendable, Equatable {
    public let light: RGBAColor
    public let dark: RGBAColor
    public let lightHighContrast: RGBAColor
    public let darkHighContrast: RGBAColor

    public init(light: RGBAColor, dark: RGBAColor,
                lightHighContrast: RGBAColor? = nil, darkHighContrast: RGBAColor? = nil) {
        self.light = light
        self.dark = dark
        self.lightHighContrast = lightHighContrast ?? light
        self.darkHighContrast = darkHighContrast ?? dark
    }

    /// Appearance-independent token (accent family): the same value on both sides.
    public init(both value: RGBAColor) {
        self.init(light: value, dark: value)
    }

    public func value(for appearance: TokenAppearance, increasedContrast: Bool = false) -> RGBAColor {
        switch (appearance, increasedContrast) {
        case (.light, false): light
        case (.dark, false): dark
        case (.light, true): lightHighContrast
        case (.dark, true): darkHighContrast
        }
    }
}

/// The two system appearances a token resolves against.
public enum TokenAppearance: CaseIterable, Sendable {
    case light, dark
}
