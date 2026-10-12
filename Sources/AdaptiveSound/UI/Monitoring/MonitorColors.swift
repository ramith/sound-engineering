import DesignTokenKit
import SwiftUI

// MARK: - Monitor Colors

/// Monitoring's BEFORE / AFTER colours (S10.8 F1, decision 4), bridged from the Kit's `MonitorPalette`:
/// BEFORE a neutral grey, AFTER the analyzer's teal → lime (light variant included), audited by R4-MON.
/// Built ONCE: every colour is appearance-dynamic, and each channel row redraws its bars at the poll rate.
enum MonitorColors {
    /// BEFORE's bars and legend swatch.
    static let beforeFill = DesignSystem.Color.from(MonitorPalette.beforeFill)
    /// BEFORE's tag.
    static let beforeText = DesignSystem.Color.from(MonitorPalette.beforeText)
    /// AFTER's tag.
    static let afterText = DesignSystem.Color.from(MonitorPalette.afterText)

    /// AFTER's legend swatch: the ramp, low → high, leading → trailing.
    static let afterSwatch = LinearGradient(
        stops: SpectrumRamp.stops.map { stop in
            Gradient.Stop(color: DesignSystem.Color.from(MonitorPalette.afterFill(at: stop.position)),
                          location: CGFloat(stop.position))
        },
        startPoint: .leading,
        endPoint: .trailing
    )

    /// AFTER's bar colours for a field of `count` bars, low → high frequency.
    static func afterFills(count: Int) -> [Color] {
        count == bandFills.count ? bandFills : makeAfterFills(count: count)
    }

    /// The monitor's own bar count (one bar per analyzer band), built on first use.
    private static let bandFills = makeAfterFills(count: SpectrumConstants.bandCount)

    private static func makeAfterFills(count: Int) -> [Color] {
        (0 ..< count).map { index in
            DesignSystem.Color.from(MonitorPalette.afterFill(at: count > 1 ? Float(index) / Float(count - 1) : 0))
        }
    }
}
