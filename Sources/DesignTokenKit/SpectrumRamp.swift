// SpectrumRamp — the analyzer's teal → lime bar ramp as Kit data (S10.8 B2a): a light/dark pair
// per stop, the bar's vertical shade, the peak caps' opacity per appearance, and the interpolation
// the bars are painted from. The app-side `SpectrumColorPalette` bridges it to SwiftUI gradients; R4-SPEC-01
// audits the same values.

import Foundation

public enum SpectrumRamp {
    /// One ramp stop: a normalized bar position (low → high frequency, left → right) and its color.
    /// `position` is a `Float` like the bar-index math that feeds the ramp, so the interpolation is
    /// bit-for-bit the shipped one.
    public struct Stop: Sendable {
        public let position: Float
        public let color: AppearancePair
    }

    /// A bar's vertical fill: the ramp color at the top, shaded toward the bottom.
    public struct Shade: Sendable {
        public let top: AppearancePair
        public let bottom: AppearancePair
    }

    /// Dark = the shipped ramp (#1F9D8B → #C8F06A), unchanged. Light = the same hues deepened so
    /// every stop clears 3:1 on the light lens (R4-SPEC-01) — the shipped lime was ~1.2:1 there.
    /// Emphasis is contrast against the surface, never an inversion (design §3.2).
    public static let stops: [Stop] = [
        Stop(position: 0.00, color: AppearancePair(
            light: RGBAColor(red: 0x0F / 255.0, green: 0x7C / 255.0, blue: 0x6C / 255.0), // #0F7C6C
            dark: RGBAColor(red: 0x1F / 255.0, green: 0x9D / 255.0, blue: 0x8B / 255.0) // #1F9D8B
        )),
        Stop(position: 0.20, color: AppearancePair(
            light: RGBAColor(red: 0x0F / 255.0, green: 0x81 / 255.0, blue: 0x6F / 255.0), // #0F816F
            dark: RGBAColor(red: 0x36 / 255.0, green: 0xC1 / 255.0, blue: 0xAB / 255.0) // #36C1AB
        )),
        Stop(position: 0.40, color: AppearancePair(
            light: RGBAColor(red: 0x10 / 255.0, green: 0x86 / 255.0, blue: 0x76 / 255.0), // #108676
            dark: RGBAColor(red: 0x4F / 255.0, green: 0xD2 / 255.0, blue: 0xC0 / 255.0) // #4FD2C0
        )),
        Stop(position: 0.60, color: AppearancePair(
            light: RGBAColor(red: 0x11 / 255.0, green: 0x90 / 255.0, blue: 0x45 / 255.0), // #119045
            dark: RGBAColor(red: 0x7F / 255.0, green: 0xE3 / 255.0, blue: 0xA8 / 255.0) // #7FE3A8
        )),
        Stop(position: 0.80, color: AppearancePair(
            light: RGBAColor(red: 0x3F / 255.0, green: 0x95 / 255.0, blue: 0x12 / 255.0), // #3F9512
            dark: RGBAColor(red: 0xA8 / 255.0, green: 0xEC / 255.0, blue: 0x84 / 255.0) // #A8EC84
        )),
        Stop(position: 1.00, color: AppearancePair(
            light: RGBAColor(red: 0x6D / 255.0, green: 0x94 / 255.0, blue: 0x12 / 255.0), // #6D9412
            dark: RGBAColor(red: 0xC8 / 255.0, green: 0xF0 / 255.0, blue: 0x6A / 255.0) // #C8F06A
        )),
    ]

    /// The bar's bottom is its top color scaled by this, both appearances (the shipped shade).
    public static let bottomShade: Double = 0.82

    /// Peak-cap opacity over the bar's own fill. Dark keeps the shipped 50%; light raises it to
    /// 85% so the caps still read on the white lens. Decorative either way (see R4-SPEC-01's
    /// exemptions).
    public static let capOpacityDark: Double = 0.5
    public static let capOpacityLight: Double = 0.85

    /// The bar fill at `position` (clamped to [0, 1]).
    public static func bar(at position: Float) -> Shade {
        let top = color(at: position)
        return Shade(top: top, bottom: AppearancePair(light: shaded(top.light), dark: shaded(top.dark)))
    }

    /// The ramp color at `position`: linear in sRGB between the two stops around it.
    public static func color(at position: Float) -> AppearancePair {
        let clamped = max(0, min(1, position))
        var lower = stops[0]
        var upper = stops[stops.count - 1]
        for index in 0 ..< stops.count - 1
            where stops[index].position <= clamped && clamped <= stops[index + 1].position {
            lower = stops[index]
            upper = stops[index + 1]
            break
        }
        let span = upper.position - lower.position
        let fraction = Double(span > 0 ? (clamped - lower.position) / span : 0)
        return AppearancePair(light: mix(lower.color.light, upper.color.light, fraction),
                              dark: mix(lower.color.dark, upper.color.dark, fraction))
    }

    private static func mix(_ lower: RGBAColor, _ upper: RGBAColor, _ fraction: Double) -> RGBAColor {
        RGBAColor(red: lower.red * (1 - fraction) + upper.red * fraction,
                  green: lower.green * (1 - fraction) + upper.green * fraction,
                  blue: lower.blue * (1 - fraction) + upper.blue * fraction)
    }

    private static func shaded(_ color: RGBAColor) -> RGBAColor {
        RGBAColor(red: color.red * bottomShade, green: color.green * bottomShade,
                  blue: color.blue * bottomShade, alpha: color.alpha)
    }
}
