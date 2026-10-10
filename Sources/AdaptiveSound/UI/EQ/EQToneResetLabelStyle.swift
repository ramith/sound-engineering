import SwiftUI

// MARK: - Tone reset label (EQ3t)

/// Reset Tone's label: the glyph and "Reset Tone" on the open card; the glyph alone on the folded
/// card's one line. Both are the system styles, so the title stays the button's VoiceOver label and
/// Voice Control name when it isn't drawn.
struct EQToneResetLabelStyle: LabelStyle {
    let isIconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if isIconOnly {
            Label(configuration).labelStyle(.iconOnly)
        } else {
            Label(configuration).labelStyle(.titleAndIcon)
        }
    }
}
