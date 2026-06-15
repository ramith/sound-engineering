import SwiftUI

// MARK: - Now Playing Tab View

struct NowPlayingTabView: View {
    @Environment(AudioViewModel.self) var viewModel

    var body: some View {
        HStack(spacing: 0) {
            LeftPanelView()
                .containerRelativeFrame(.horizontal, count: 2, span: 1, spacing: 0)

            RightPanelView()
                .containerRelativeFrame(.horizontal, count: 2, span: 1, spacing: 0)
                .padding(16)
                .background(Color.asCard)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.asHairline)
                        .frame(width: 0.5)
                }
        }
        .background(Color.asWindow)
    }
}
