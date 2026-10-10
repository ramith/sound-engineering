import SwiftUI

// MARK: - Nav-rail row symbol

/// The SF symbol leading a Library rail row (`NavRow`): body-sized, in an 18 pt column so the labels
/// line up whatever the glyph's width. Decorative — `NavRow` hides it from VoiceOver.
struct NavRowSymbol: View {
    let name: String

    var body: some View {
        Image(systemName: name)
            .font(DesignSystem.Font.body)
            .frame(width: 18)
    }
}
