import SwiftUI

struct SettingsTabView: View {
    var body: some View {
        VStack(spacing: 24) {
            // Placeholder text. No "Settings" title here — the tab and the header
            // breadcrumb already name this screen; repeating it was redundant.
            VStack(spacing: 8) {
                Text("Coming in Phase 1b")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.asLabelSecond)
            }
            .padding(.top, 32)

            // Settings controls (all disabled)
            VStack(spacing: 12) {
                SettingsControlRow(
                    title: "Hearing Profile",
                    icon: "ear.fill"
                )

                SettingsControlRow(
                    title: "Device Correction EQ",
                    icon: "slider.horizontal.3"
                )

                SettingsControlRow(
                    title: "Loudness Compensation",
                    icon: "speaker.wave.2.fill"
                )

                SettingsControlRow(
                    title: "About/Help",
                    icon: "questionmark.circle.fill"
                )
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 16)
    }
}

// MARK: - Settings Control Row

struct SettingsControlRow: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.asLabelTertiary)
                .frame(width: 24)

            Text(title)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.asLabelTertiary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.asLabelTertiary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(Color.asCard)
        .cornerRadius(9)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.asHairline, lineWidth: 0.5))
        .opacity(0.5)
    }
}
