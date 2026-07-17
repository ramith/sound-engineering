import SwiftUI

// MARK: - Now Playing Tab View

struct NowPlayingTabView: View {
    @Environment(AudioViewModel.self) var viewModel

    var body: some View {
        HStack(spacing: 0) {
            LeftPanelView()
                .containerRelativeFrame(.horizontal, count: 2, span: 1, spacing: 0)

            RightPanelView()
                // Pad BEFORE constraining to half-width so the inset stays inside
                // the panel (padding after containerRelativeFrame overflowed the
                // window edge and clipped the right-aligned LUFS readouts).
                .padding(16)
                .containerRelativeFrame(.horizontal, count: 2, span: 1, spacing: 0)
                .background(Color.asCard)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.asHairline)
                        .frame(width: 0.5)
                }
        }
        // The ambient glow field (S10.7 PR 2): paints the window base + the three 8a glows
        // behind the whole tab. Other tabs keep the plain base until the S10.8 sweep (D1).
        .background { GlowField() }
    }
}
