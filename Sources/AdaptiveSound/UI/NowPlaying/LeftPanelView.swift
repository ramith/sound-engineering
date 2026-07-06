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
        // Scrolls within its pane (L4b): the Now Playing detail stack (spectrum → gain → track
        // info) can be taller than the shell's bounded content region on a short window, so it
        // must scroll rather than be clipped. On a tall window it simply sits top-aligned.
        // Transport (scrubber + play controls) moved to the global footer bar in L3.
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                SpectrumAnalyzerView()
                    .frame(height: 50)
                    .padding(.leading, Layout.leadingPad)
                    .padding(.trailing, Layout.trailingPad)
                    .padding(.vertical, Layout.spectrumVPad)
                    // Double-click the spectrum to open the dedicated Monitoring tab (per-channel
                    // before/after). Single-tap is unaffected (the spectrum has no single-tap action).
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { viewModel.selectedTab = .monitoring }
                    .help("Double-click to open Monitoring")

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

                NowPlayingInfoView()
                    .padding(.leading, Layout.leadingPad)
                    .padding(.trailing, Layout.trailingPad)
                    .padding(.vertical, Layout.sectionVPad)
            }
        }
    }
}
