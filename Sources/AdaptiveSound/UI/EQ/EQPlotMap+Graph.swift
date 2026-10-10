import DesignTokenKit
import EQEditKit
import SwiftUI

// MARK: - The EQ graph's plot inside its lens

extension EQPlotMap {
    /// The plot inside an EQ graph lens of `size`: inset for the strip and region names above, the
    /// frequency axis below and the dB labels leading (`EQScreenLayout`). The painter, the silhouette, the
    /// handle and the drag's hit-test all place by this one map.
    static func eqGraph(in size: CGSize) -> EQPlotMap {
        EQPlotMap(left: CGFloat(EQScreenLayout.plotInsetLeading),
                  right: size.width - CGFloat(EQScreenLayout.plotInsetTrailing),
                  top: CGFloat(EQScreenLayout.plotInsetTop),
                  bottom: size.height - CGFloat(EQScreenLayout.plotInsetBottom))
    }
}
