import DesignTokenKit
import SwiftUI

/// The Settings tab (S10.8 F2): one floating glass card per section — Output Device, then Pure Mode —
/// in a column at most the readable width, centred in the tab on the Twin Panels insets
/// (`SettingsLayout`), over the tab's glow. The column scrolls on a short window (fixes bug 4 —
/// Settings clipped its lower sections) with the scroll clip off, so the cards' shadows aren't cut at
/// its edges; the shell's content region still bounds them.
struct SettingsTabView: View {
    @Environment(AudioViewModel.self) private var audioViewModel
    @Environment(EQViewModel.self) private var eqViewModel

    var body: some View {
        // edgeToEdge: the column brings its own (Twin Panels) insets rather than Screen's.
        Screen(mode: .stack, edgeToEdge: true) {
            VStack(spacing: CGFloat(SettingsLayout.cardGap)) {
                OutputDeviceSettingsSection(audioViewModel: audioViewModel)
                PureModeSettingsSection(audioViewModel: audioViewModel, eqPresetName: eqViewModel.summary)
            }
            .frame(maxWidth: CGFloat(SettingsLayout.columnMaxWidth))
            .padding(.top, CGFloat(SettingsLayout.insetTop))
            .padding(.horizontal, CGFloat(SettingsLayout.insetHorizontal))
            .padding(.bottom, CGFloat(SettingsLayout.insetBottom))
        }
        .scrollClipDisabled()
    }
}
