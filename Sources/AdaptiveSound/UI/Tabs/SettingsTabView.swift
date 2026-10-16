import DesignTokenKit
import SwiftUI

/// The Settings tab (S10.8 F2): one floating glass card per section — Output Device, Pure Mode, then
/// Formats (R1.1-A) — in a column at most the readable width, centred in the tab on the Twin Panels
/// insets (`SettingsLayout`), over the app glow. The column scrolls on a short window (fixes bug 4 —
/// Settings clipped its lower sections). The scroll view spans the whole content region and the cards
/// sit inside its insets, so its clip — the region's own edge — never cuts their shadows at rest, and
/// scrolled-away content never draws (or takes clicks) over the chrome.
struct SettingsTabView: View {
    @Environment(AudioViewModel.self) private var audioViewModel
    @Environment(EQViewModel.self) private var eqViewModel

    var body: some View {
        // edgeToEdge: the column brings its own (Twin Panels) insets rather than Screen's.
        Screen(edgeToEdge: true) {
            VStack(spacing: CGFloat(SettingsLayout.cardGap)) {
                OutputDeviceSettingsSection(audioViewModel: audioViewModel)
                PureModeSettingsSection(audioViewModel: audioViewModel, eqPresetName: eqViewModel.summary)
                FormatsSettingsSection(audioViewModel: audioViewModel)
            }
            .frame(maxWidth: CGFloat(SettingsLayout.columnMaxWidth))
            .padding(.top, CGFloat(SettingsLayout.insetTop))
            .padding(.horizontal, CGFloat(SettingsLayout.insetHorizontal))
            .padding(.bottom, CGFloat(SettingsLayout.insetBottom))
        }
    }
}
