#if DEBUG
    import DesignTokenKit
    import SwiftUI

    // MARK: - Light backdrop switch: the environment feed

    /// Feeds the `Debug ▸ Light Background` pick (`LightBackdropMenu`, persisted under its
    /// `defaultsKey`) to the window's environment, so the window base and the glow gate repaint
    /// live (S10.8 B2b). Applied once, to the main window's content. TEMPORARY, like the menu.
    struct LightBackdropSwitch: ViewModifier {
        @AppStorage(LightBackdropMenu.defaultsKey) private var backdrop = LightBackdrop.designed

        func body(content: Content) -> some View {
            content.environment(\.lightBackdrop, backdrop)
        }
    }
#endif
