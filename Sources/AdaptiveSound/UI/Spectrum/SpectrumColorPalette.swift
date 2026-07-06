import SwiftUI

// MARK: - RGBValue

/// RGB value stored as (red, green, blue) in normalized [0, 1] range.
struct RGBValue {
    let r: Double
    let g: Double
    let b: Double
}

// MARK: - Spectrum Color Palette

/// Frequency-based color palette for spectrum visualization.
/// Interpolated linearly in sRGB space from low frequencies (left, teal) to high (right, lime).
enum SpectrumColorPalette {
    struct Stop {
        let t: Float
        let rgb: RGBValue
    }

    // Palette: Teal → Lime (low freq to high freq)
    static let tealoLime: [Stop] = [
        Stop(t: 0.00, rgb: RGBValue(r: 0x1F / 255.0, g: 0x9D / 255.0, b: 0x8B / 255.0)), // #1F9D8B
        Stop(t: 0.20, rgb: RGBValue(r: 0x36 / 255.0, g: 0xC1 / 255.0, b: 0xAB / 255.0)), // #36C1AB
        Stop(t: 0.40, rgb: RGBValue(r: 0x4F / 255.0, g: 0xD2 / 255.0, b: 0xC0 / 255.0)), // #4FD2C0
        Stop(t: 0.60, rgb: RGBValue(r: 0x7F / 255.0, g: 0xE3 / 255.0, b: 0xA8 / 255.0)), // #7FE3A8
        Stop(t: 0.80, rgb: RGBValue(r: 0xA8 / 255.0, g: 0xEC / 255.0, b: 0x84 / 255.0)), // #A8EC84
        Stop(t: 1.00, rgb: RGBValue(r: 0xC8 / 255.0, g: 0xF0 / 255.0, b: 0x6A / 255.0)), // #C8F06A
    ]
}

// MARK: - Gradient Utilities

extension SpectrumColorPalette {
    /// Returns a vertical linear gradient for a spectrum bar at normalized position t [0, 1].
    static func gradientAt(_ t: Float) -> LinearGradient {
        let clamped = max(0, min(1, t))

        var lower = tealoLime[0]
        var upper = tealoLime[tealoLime.count - 1]

        for i in 0 ..< tealoLime.count - 1 {
            if tealoLime[i].t <= clamped && clamped <= tealoLime[i + 1].t {
                lower = tealoLime[i]
                upper = tealoLime[i + 1]
                break
            }
        }

        let localT = Double((upper.t > lower.t) ? (clamped - lower.t) / (upper.t - lower.t) : 0)
        let rgb = RGBValue(
            r: lower.rgb.r * (1 - localT) + upper.rgb.r * localT,
            g: lower.rgb.g * (1 - localT) + upper.rgb.g * localT,
            b: lower.rgb.b * (1 - localT) + upper.rgb.b * localT
        )

        let topColor = Color(red: rgb.r, green: rgb.g, blue: rgb.b)
        let bottomColor = Color(red: rgb.r * 0.82, green: rgb.g * 0.82, blue: rgb.b * 0.82)

        return LinearGradient(
            gradient: Gradient(stops: [
                .init(color: topColor, location: 0),
                .init(color: bottomColor, location: 1),
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
