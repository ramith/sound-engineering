import DesignTokenKit
import SwiftUI

// MARK: - Settings card (S10.8 F2 — Settings on the app's card grammar)

/// One Settings section as a floating glass card, on the `.panel` glass the Library's and the EQ's
/// cards wear: the section's title — with a control trailing it, as the Library card header carries
/// its pills — over the section's rows (`SettingsLayout`). It paints no backdrop of its own: the app
/// glow (`TabContentView`) shows around it. VoiceOver reads it as one container named by its title.
struct SettingsCard<Accessory: View, Content: View>: View {
    let title: String
    /// The control on the title row's trailing edge (Output Device's device pill), or nothing.
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(GlassDecor.panelRadius), style: .continuous)
        VStack(alignment: .leading, spacing: CGFloat(SettingsLayout.rowGap)) {
            // The spacer is the row's one gap, so the row is exactly what LAY-SET-01b budgets.
            HStack(spacing: 0) {
                Text(title)
                    .font(DesignSystem.Font.sectionTitle)
                    .foregroundStyle(DesignSystem.Color.label)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: CGFloat(SettingsLayout.titleAccessoryGap))
                accessory
            }
            .frame(minHeight: CGFloat(SettingsLayout.titleRowMinHeight))
            content
        }
        .padding(CGFloat(SettingsLayout.cardPadding))
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(.panel, in: shape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

extension SettingsCard where Accessory == EmptyView {
    /// A card with nothing beside its title.
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, accessory: { EmptyView() }, content: content)
    }
}
