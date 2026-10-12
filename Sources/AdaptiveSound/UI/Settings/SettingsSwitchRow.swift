import SwiftUI

// MARK: - Settings switch row (S10.8 F2)

/// A Settings switch: its title over a line of helper text, with the app's switch (`GlassSwitchStyle`
/// — tinted from the accent tokens, never the system blue) on the row's trailing edge, where helper
/// text that changes length with the switch can't move it.
struct SettingsSwitchRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.Font.body)
                    .foregroundStyle(DesignSystem.Color.label)
                Text(detail)
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(GlassSwitchStyle())
    }
}
