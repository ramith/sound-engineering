import DesignTokenKit
import SwiftUI

// MARK: - Spectrum Color Palette

/// The analyzer's bar fills, bridged from the Kit's `SpectrumRamp` — the teal → lime light/dark
/// pair, interpolated in sRGB from low frequencies (left, teal) to high (right, lime) and audited by
/// R4-SPEC-01. Each bar is a vertical gradient, its ramp colour at the top shaded toward the bottom;
/// a peak cap wears its bar's gradient at the cap opacity (`spectrumCapOpacity`).
///
/// Resolved, and built once per bar count and appearance: the lens fills 176 gradients a frame, and a
/// `Canvas` resolves a dynamic (light / dark) colour again on every fill — 3 ms of a 4.4 ms frame
/// when they were dynamic. Resolved for the appearance being drawn, they are plain colours.
@MainActor
enum SpectrumColorPalette {
    /// The vertical bar gradients (top → bottom) for a field of `count` bars, left → right, in
    /// `environment`'s appearance (its colour scheme and contrast).
    static func barGradients(count: Int, in environment: EnvironmentValues) -> [Gradient] {
        let key = Key(count: count, scheme: environment.colorScheme, contrast: environment.colorSchemeContrast)
        if let gradients = built[key] {
            return gradients
        }
        let gradients = (0 ..< count).map { index in
            let shade = SpectrumRamp.bar(at: count > 1 ? Float(index) / Float(count - 1) : 0)
            return Gradient(stops: [
                .init(color: resolved(shade.top, in: environment), location: 0),
                .init(color: resolved(shade.bottom, in: environment), location: 1),
            ])
        }
        built[key] = gradients
        return gradients
    }

    /// One appearance's gradients for one bar count.
    private struct Key: Hashable {
        let count: Int
        let scheme: ColorScheme
        let contrast: ColorSchemeContrast
    }

    private static var built: [Key: [Gradient]] = [:]

    private static func resolved(_ pair: AppearancePair, in environment: EnvironmentValues) -> Color {
        Color(DesignSystem.Color.from(pair).resolve(in: environment))
    }
}
