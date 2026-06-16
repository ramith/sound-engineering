import SwiftUI

// MARK: - Right Panel

struct RightPanelView: View {
    @Environment(AudioViewModel.self) var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NowPlayingWidget()

            // Live loudness meters (replaces the previously-hardcoded module list).
            LoudnessMetersView()

            // Intensity
            VStack(alignment: .leading, spacing: 8) {
                Text("Intensity")
                    .font(.caption.weight(.semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.asLabelSecond)

                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [2]))
                        .foregroundStyle(Color.asHairline)

                    VStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.asLabelTertiary)

                        Text("No module selected")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.asLabelTertiary)
                    }
                }
                .frame(height: 80)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Intensity: no module selected")
            }

            Spacer()
        }
    }
}
