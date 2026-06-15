import SwiftUI

// MARK: - Right Panel

struct RightPanelView: View {
    @Environment(AudioViewModel.self) var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NowPlayingWidget()

            // Active Modules
            VStack(alignment: .leading, spacing: 8) {
                Text("Active Modules")
                    .font(.caption.weight(.semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.asLabelSecond)

                ForEach(
                    [("EQ", true), ("Clarity", false), ("BRII", false),
                     ("Loudness", false), ("Limiter", true)],
                    id: \.0
                ) { name, active in
                    HStack(spacing: 8) {
                        Image(systemName: active ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(active ? Color.asAccent : Color.asLabelTertiary)
                            .font(.system(size: 16))
                        Text(name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.asLabel)
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(name), \(active ? "active" : "inactive")")
                }
            }

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
