// MonitorPalette — the Monitoring tab's BEFORE / AFTER colours as Kit data (S10.8 F1, decision 4):
// BEFORE is a neutral grey, AFTER the analyzer's teal → lime ramp (`SpectrumRamp`, its light variant
// included). Every value is DERIVED, no new literal. Split text-vs-fill like the rest of the palette:
// each side has a fill (its bars and legend swatch, non-text 3:1) and a text colour (its tag, AA).
// R4-MON audits these values where they sit: each channel's lens (S10.8 G1; F1 picked them on the row
// card the lens replaced), over the app glow.

import Foundation

public enum MonitorPalette {
    /// BEFORE's bars and legend swatch: `labelTertiary`'s grey. It clears 3:1 on the channel's lens over
    /// the app glow (R4-MON-01: 4.6:1 at its weakest, dark; 4.2:1 at the bars' foot, where the dark
    /// bleed lifts the lens — R4-MON-01b). It sits mid-ramp in both appearances, so neither half of the
    /// lens outweighs the other.
    public static let beforeFill = Palette.labelTertiary

    /// BEFORE's tag: `labelNav`'s grey, a peer of AFTER's teal tag in weight. F1 chose it because
    /// `labelSecondary` measured 4.4:1 on the dark row card over the glow's core, under AA; on G1's
    /// darker lens `labelSecondary` would clear (5.5:1), but the tag keeps `labelNav` (R4-MON-03: 8.4:1).
    public static let beforeText = Palette.labelNav

    /// AFTER's tag: the teal text token. The ramp itself cannot be text: its teal end measures 4.46:1 on
    /// the dark lens over the glow, and its light lime 3.5:1 on the light lens (R4-MON-03).
    public static let afterText = Palette.accentText

    /// AFTER's bar at `position` (0 = the lowest band, 1 = the highest) and its legend swatch: the
    /// analyzer ramp's colour, FLAT. The analyzer's vertical shade would take the teal foot to 2.6:1
    /// where the bars meet the dark lens's bleed (R4-MON-01b).
    public static func afterFill(at position: Float) -> AppearancePair {
        SpectrumRamp.color(at: position)
    }
}
