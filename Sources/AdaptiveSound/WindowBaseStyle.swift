import DesignTokenKit
import SwiftUI

/// The window base as a `ShapeStyle` (S10.8 B2b): it resolves the environment's light backdrop
/// to that backdrop's window pair, bridged through the same dynamic token color every other
/// surface uses — so dark paints exactly today's `Palette.window` (every backdrop shares its dark
/// side) and light follows the live pick, no relaunch. `DesignSystem.Color.window` IS this style
/// while the backdrop is switchable; after the founder's pick it goes back to a plain
/// `from(Palette.window)` color and this type is deleted.
struct WindowBaseStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> SwiftUI.Color {
        DesignSystem.Color.from(environment.lightBackdrop.window)
    }
}
