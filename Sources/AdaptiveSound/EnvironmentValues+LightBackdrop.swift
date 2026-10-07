import DesignTokenKit
import SwiftUI

extension EnvironmentValues {
    #if DEBUG
        /// The light window backdrop (S10.8 B2b): which window base paints, and whether the glow
        /// field paints in light. DEBUG only, the founder flips it live (`Debug ▸ Light Background`,
        /// `LightBackdropMenu` / `LightBackdropSwitch`) and the picture-sheet renderer sets it per
        /// sheet. Read only by `WindowBaseStyle` and the sanctioned shims in DesignSystemGlass.swift.
        @Entry var lightBackdrop: LightBackdrop = .designed
    #else
        /// Release has no switch: always the designed backdrop.
        var lightBackdrop: LightBackdrop {
            .designed
        }
    #endif
}
