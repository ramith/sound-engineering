import SwiftUI

// MARK: - Left Panel

struct LeftPanelView: View {
    @Environment(AudioViewModel.self) var viewModel

    /// Semantic layout constants — adjust once, affects every section.
    private enum Layout {
        /// "Artistic" breathing room from the window's left edge.
        static let leadingPad: CGFloat = 28
        static let trailingPad: CGFloat = 20
        /// Consistent vertical rhythm between all sections.
        static let sectionVPad: CGFloat = 14
        /// The spectrum header warrants slightly more top air.
        static let spectrumVPad: CGFloat = 16
    }

    var body: some View {
        VStack(spacing: 0) {
            SpectrumAnalyzerView()
                .frame(height: 50)
                .padding(.leading, Layout.leadingPad)
                .padding(.trailing, Layout.trailingPad)
                .padding(.vertical, Layout.spectrumVPad)

            PlayControlsView()
                .padding(.leading, Layout.leadingPad)
                .padding(.trailing, Layout.trailingPad)
                .padding(.vertical, Layout.sectionVPad)

            MasterGainSliderView()
                .padding(.leading, Layout.leadingPad)
                .padding(.trailing, Layout.trailingPad)
                .padding(.vertical, Layout.sectionVPad)

            // Divider() does not respond to foregroundStyle on macOS —
            // a filled Rectangle is the only reliable way to honour the
            // hairline design token.
            Rectangle()
                .fill(Color.asHairline)
                .frame(height: 0.5)

            PlaylistView()
                .padding(.leading, Layout.leadingPad)
                .padding(.trailing, Layout.trailingPad)
                .padding(.vertical, Layout.sectionVPad)
        }
    }
}
