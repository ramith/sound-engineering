// LightBackdrop — the three candidate LIGHT window backdrops (S10.8 Sprint B2b). The founder picks
// one by trying them live (a DEBUG-only menu, `Debug ▸ Light Background`); the two losers and this
// enum are then deleted, folding the winner into `Palette.window` and the RES-04 resolver. Dark never
// differs: every candidate's dark side is `Palette.window.dark`, and the glow field paints in dark
// under all three. Plain data, like the rest of the Kit — the app reads it through the environment.

import Foundation

public enum LightBackdrop: String, CaseIterable, Sendable {
    /// A — the plain grey window (#EDEDED, `Palette.window`); depth comes from the card shadows.
    case noGlow
    /// B — the same grey plus the pale glow pool (the `Palette.glow*` light pastels), which only
    /// ever BRIGHTENS the window (GLOW-01).
    case paleGlow
    /// C — a very light teal-grey window (#E3EEEC), no glow.
    case tintedBase

    /// The designer's recommendation (B): the default, and all a Release build paints — Release
    /// has no switch.
    public static let designed: LightBackdrop = .paleGlow

    /// The window base this backdrop paints — a light-only choice: the dark side is always
    /// `Palette.window.dark`.
    public var window: AppearancePair {
        switch self {
        case .noGlow, .paleGlow:
            Palette.window
        case .tintedBase:
            AppearancePair(light: RGBAColor(red: 227.0 / 255.0, green: 238.0 / 255.0, blue: 236.0 / 255.0),
                           dark: Palette.window.dark)
        }
    }

    /// Whether the ambient glow field paints in LIGHT appearance (RES-04's light rule). Dark paints
    /// it under every backdrop.
    public var glowsInLight: Bool {
        self == .paleGlow
    }
}
