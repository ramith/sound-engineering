// R4-DIALOG — the themed dialog's contrast audit (S10.8 EQ fix: `AppDialog`). Own file, same posture as
// R4-CHIP: shares only the `ratio`/threshold helpers with the base R4 suite.

import DesignTokenKit
import Testing

/// The dialog sits on the window colour (the sheet's own surface). Its pills: Cancel is the neutral
/// header pill (`label` on `card`, R4-CHIP's pair), the primary action the teal pill (R4-TAB-01), and a
/// destructive action `statusErrorText` on the `destructiveFill` tint, edged in `statusErrorText`.
@Suite("Contrast audit — the themed dialog (R4-DIALOG)")
struct DialogAuditTests {
    @Test("R4-DIALOG-01: the destructive pill's text clears AA, and its edge 3:1, in both appearances")
    func destructivePill() {
        for appearance in TokenAppearance.allCases {
            let window = Palette.window.value(for: appearance)
            let pill = Palette.destructiveFill.value(for: appearance).over(window)
            let text = ContrastAuditTests.ratio(label: Palette.statusErrorText, on: pill, appearance)
            #expect(text >= ContrastAuditTests.textAA,
                    "statusErrorText on destructiveFill⊕window (\(appearance)) = \(text)")
            // The edge separates the pill from the window around it (WCAG 1.4.11).
            let edge = ContrastAuditTests.ratio(label: Palette.statusErrorText, on: window, appearance)
            #expect(edge >= ContrastAuditTests.nonTextAA, "statusErrorText edge on window (\(appearance)) = \(edge)")
        }
    }

    @Test("R4-DIALOG-02: the dialog's title, message and Cancel read AA on the window colour")
    func dialogText() {
        for appearance in TokenAppearance.allCases {
            let window = Palette.window.value(for: appearance)
            let card = Palette.card.value(for: appearance).over(window)
            for (name, token, surface) in [("label", Palette.label, window),
                                           ("labelSecondary", Palette.labelSecondary, window),
                                           ("label on Cancel", Palette.label, card)] {
                let ratio = ContrastAuditTests.ratio(label: token, on: surface, appearance)
                #expect(ratio >= ContrastAuditTests.textAA, "\(name) (\(appearance)) = \(ratio)")
            }
        }
    }
}
