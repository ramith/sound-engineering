import SwiftUI

// MARK: - EQ output toast

/// The output-switch toast (Sprint EQ, UI plan §4.4) on the shell's toast host: when the sound moves
/// to an output whose EQ differs, "AirPods Pro · Late Night" for 3 s, on every tab. Tapping opens
/// the EQ tab. Raised by `EQViewModel.outputDidChange(to:)`; with the window closed the slot still
/// switches and simply nothing shows.
struct EQOutputToast: View {
    @Environment(EQViewModel.self) private var eq
    @Environment(AudioViewModel.self) private var viewModel

    var body: some View {
        ShellToastHost(toast: eq.outputToast.toast, systemImage: "slider.vertical.3", hint: "Opens the Equalizer") {
            viewModel.selectedTab = .eq
            eq.outputToast.dismiss()
        }
    }
}
