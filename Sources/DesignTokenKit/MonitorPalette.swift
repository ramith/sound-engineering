// MonitorPalette — the Monitoring tab's BEFORE / AFTER colours as Kit data (S10.8 F1, decision 4):
// BEFORE is a neutral grey, AFTER the analyzer's teal → lime ramp (`SpectrumRamp`, its light variant
// included). Every value is DERIVED, no new literal. Split text-vs-fill like the rest of the palette:
// each side has a fill (its bars and legend swatch, non-text 3:1) and a text colour (its tag, AA).
// R4-MON audits these values where they sit: the row card, over the app glow.

import Foundation

public enum MonitorPalette {
    /// BEFORE's bars and legend swatch: `labelTertiary`'s grey, the quietest one that clears 3:1 on the
    /// row card over the app glow (R4-MON-01). It sits mid-ramp in both appearances, so neither side of
    /// the row outweighs the other.
    public static let beforeFill = Palette.labelTertiary

    /// BEFORE's tag: `labelNav`'s grey. `labelSecondary` measures 4.4:1 on the dark row card over the
    /// glow's core, under AA (R4-MON-03).
    public static let beforeText = Palette.labelNav

    /// AFTER's tag: the teal text token. The ramp itself cannot be text: its teal end measures 3.1:1 on
    /// the dark row card over the glow's core, and its light lime 3.6:1 on the light card (R4-MON-03).
    public static let afterText = Palette.accentText

    /// AFTER's bar at `position` (0 = the lowest band, 1 = the highest) and its legend swatch: the
    /// analyzer ramp's colour, FLAT. The analyzer's vertical shade would take the teal foot to 2.2:1 on
    /// the dark row card over the glow's core (R4-MON-01).
    public static func afterFill(at position: Float) -> AppearancePair {
        SpectrumRamp.color(at: position)
    }
}
