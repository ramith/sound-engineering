import SwiftUI

// MARK: - Play Controls

struct PlayControlsView: View {
    @Environment(AudioViewModel.self) var viewModel

    private enum Layout {
        static let skipButtonSize: CGFloat = 52
        static let playButtonSize: CGFloat = 72
        /// Symbol scale: ~38% of container keeps proportions comfortable.
        static let skipSymbolSize: CGFloat = 20
        static let playSymbolSize: CGFloat = 26
        /// Gap between the three buttons.
        static let buttonSpacing: CGFloat = 24
    }

    var body: some View {
        HStack(spacing: Layout.buttonSpacing) {
            TransportButton(
                accessibilityLabel: "Previous track",
                systemImage: "backward.fill",
                symbolSize: Layout.skipSymbolSize,
                containerSize: Layout.skipButtonSize
            ) {
                viewModel.previousTrack()
            }

            // Play / Pause — larger, gradient-filled, prominent.
            Button {
                if viewModel.isPlaying {
                    viewModel.stopPlayback()
                } else {
                    viewModel.play()
                }
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: Layout.playSymbolSize, weight: .semibold))
                    .foregroundStyle(.white)
                    // contentShape ensures the full circle area is hittable,
                    // not just the symbol's bounding box.
                    .frame(width: Layout.playButtonSize, height: Layout.playButtonSize)
                    .background(LinearGradient.asIconFill)
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")

            TransportButton(
                accessibilityLabel: "Next track",
                systemImage: "forward.fill",
                symbolSize: Layout.skipSymbolSize,
                containerSize: Layout.skipButtonSize
            ) {
                viewModel.nextTrack()
            }
        }
        .frame(maxWidth: .infinity)
    }
}
