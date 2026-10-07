import DesignTokenKit
import SwiftUI

// MARK: - Spectrum Color Palette

/// The analyzer's bar fills, bridged from the Kit's `SpectrumRamp` — the teal → lime light/dark
/// pair, interpolated in sRGB from low frequencies (left, teal) to high (right, lime) and audited by
/// R4-SPEC-01. A peak cap wears its bar's fill under `.spectrumCapOpacity()`. Built ONCE per bar
/// count: the analyzer redraws at 20 Hz and every color here is appearance-dynamic, so rebuilding
/// per frame would mint thousands of colors a second.
enum SpectrumColorPalette {
    /// The vertical bar gradients for a field of `count` bars, left → right.
    static func barFills(count: Int) -> [LinearGradient] {
        count == displayFills.count ? displayFills : makeFills(count: count)
    }

    /// The analyzer's own bar count, built on first use.
    private static let displayFills = makeFills(count: SpectrumConstants.displayBarCount)

    private static func makeFills(count: Int) -> [LinearGradient] {
        (0 ..< count).map { index in
            let shade = SpectrumRamp.bar(at: count > 1 ? Float(index) / Float(count - 1) : 0)
            return LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: DesignSystem.Color.from(shade.top), location: 0),
                    .init(color: DesignSystem.Color.from(shade.bottom), location: 1),
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
