import DesignTokenKit
import SwiftUI

// MARK: - EQ Equalizer card (Sprint EQ, EQ3 — the rail's first card)

/// "Equalizer" with its On/Off switch (`GlassSwitchStyle`), over the presets list. The card hugs its
/// content and, where the window is too short, its list scrolls inside it — the switch stays put. Any
/// edit turns an Off EQ on; VoiceOver hears "Equalizer on" then (unless its focus is on the switch,
/// which already said so).
struct EQEqualizerCard: View {
    @Environment(EQViewModel.self) private var eq
    let save: () -> Void

    /// The presets list's natural height (the card hugs it plus the title row and padding).
    @State private var listHeight: CGFloat = 0
    @AccessibilityFocusState private var switchHasVoiceOverFocus: Bool

    var body: some View {
        @Bindable var eq = eq
        VStack(spacing: 0) {
            Toggle(isOn: $eq.isOn) {
                Text("Equalizer")
                    .font(DesignSystem.Font.sectionTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(GlassSwitchStyle())
            .accessibilityFocused($switchHasVoiceOverFocus)
            .padding(.horizontal, DesignSystem.LayoutMetrics.railRowInset)
            .frame(height: CGFloat(EQScreenLayout.titleRowHeight))
            EQPresetList(save: save, contentHeight: $listHeight)
        }
        .padding(CGFloat(EQScreenLayout.railCardPadding))
        .huggingGlassPanel(contentHeight: hugHeight)
        .onChange(of: eq.isOn) { wasOn, isOn in
            if isOn, !wasOn, !switchHasVoiceOverFocus {
                AccessibilityNotification.Announcement("Equalizer on").post()
            }
        }
    }

    /// The card's natural height; 0 (fill for a pass) until the list is measured.
    private var hugHeight: CGFloat {
        listHeight > 0 ? listHeight + CGFloat(EQScreenLayout.titleRowHeight + 2 * EQScreenLayout.railCardPadding) : 0
    }
}
