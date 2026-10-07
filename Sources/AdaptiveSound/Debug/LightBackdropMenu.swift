#if DEBUG
    import DesignTokenKit
    import SwiftUI

    // MARK: - Light backdrop switch: the menu

    /// `Debug ▸ Light Background ▸ A · No glow / B · Pale glow / C · Tinted base` (S10.8 B2b): the
    /// founder tries the three light window backdrops in the running app (`make run`, in light
    /// appearance) and picks one. The active one carries the checkmark; the pick persists in the
    /// standard defaults across relaunches and repaints the window at once (`LightBackdropSwitch`
    /// feeds it to the environment). Release builds have neither and paint the designed backdrop.
    /// TEMPORARY: deleted with the two losing backdrops after the pick.
    struct LightBackdropMenu: Commands {
        /// The persisted pick (a `LightBackdrop` raw value), shared with `LightBackdropSwitch`.
        static let defaultsKey = "debug.lightBackdrop.v1"

        @AppStorage(defaultsKey) private var backdrop = LightBackdrop.designed

        var body: some Commands {
            CommandMenu("Debug") {
                Picker("Light Background", selection: $backdrop) {
                    ForEach(LightBackdrop.allCases, id: \.self) { backdrop in
                        Text(Self.title(for: backdrop)).tag(backdrop)
                    }
                }
            }
        }

        /// The founder-facing name: the letter of the designer's option sheets, then what it is.
        private static func title(for backdrop: LightBackdrop) -> String {
            switch backdrop {
            case .noGlow: "A · No glow"
            case .paleGlow: "B · Pale glow"
            case .tintedBase: "C · Tinted base"
            }
        }
    }
#endif
