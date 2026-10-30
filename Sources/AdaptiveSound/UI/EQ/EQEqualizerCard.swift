import DesignTokenKit
import SwiftUI

// MARK: - EQ Equalizer card (Sprint EQ, EQ3 — the rail's first card)

/// "Equalizer" with its On/Off switch (`GlassSwitchStyle`), over the presets list. The card hugs its
/// content and, where the window is too short, its list scrolls inside it — the switch stays put. Any
/// edit turns an Off EQ on; VoiceOver hears "Equalizer on" then (unless its focus is on the switch,
/// which already said so). While Pure plays the switch is inert and the shared "Not in bit-perfect mode" note
/// sits under it, with Leave Pure (R1.1-B, US-R1F-20).
struct EQEqualizerCard: View {
    @Environment(EQViewModel.self) private var eq
    @Environment(AudioViewModel.self) private var audio
    let save: () -> Void
    /// Opens the Rename sheet for one of My Presets.
    let rename: (String) -> Void

    /// The presets list's natural height (the card hugs it plus the title row and padding).
    @State private var listHeight: CGFloat = 0
    /// The Pure note's measured height (0 while the EQ works).
    @State private var noteHeight: CGFloat = 0
    @AccessibilityFocusState private var switchHasVoiceOverFocus: Bool

    var body: some View {
        @Bindable var eq = eq
        let availability = audio.dspRowAvailability
        VStack(spacing: 0) {
            Toggle(isOn: $eq.isOn) {
                Text("Equalizer")
                    .font(DesignSystem.Font.sectionTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(GlassSwitchStyle())
            .bitPerfectGate(.equalizer, availability)
            .accessibilityFocused($switchHasVoiceOverFocus)
            .padding(.horizontal, DesignSystem.LayoutMetrics.railRowInset)
            .frame(height: CGFloat(EQScreenLayout.titleRowHeight))
            if !availability.isLive {
                BitPerfectRowNote(row: .equalizer, availability: availability, leavePure: audio.leavePure)
                    .padding(.horizontal, DesignSystem.LayoutMetrics.railRowInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { noteHeight = $0 }
            }
            EQPresetList(save: save, rename: rename, contentHeight: $listHeight)
        }
        .padding(CGFloat(EQScreenLayout.railCardPadding))
        .huggingGlassPanel(contentHeight: hugHeight)
        .onChange(of: eq.isOn) { wasOn, isOn in
            if isOn, !wasOn, !switchHasVoiceOverFocus {
                AccessibilityNotification.Announcement("Equalizer on").post()
            }
        }
    }

    /// The card's natural height (the Pure note's too, while it shows); 0 (fill for a pass) until the list is
    /// measured.
    private var hugHeight: CGFloat {
        let note = audio.dspRowAvailability.isLive ? 0 : noteHeight
        return listHeight > 0
            ? listHeight + note + CGFloat(EQScreenLayout.titleRowHeight + 2 * EQScreenLayout.railCardPadding) : 0
    }
}
