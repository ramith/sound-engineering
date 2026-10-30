import SettingsKit

// MARK: - AudioViewModel: the DSP rows in Pure, and "Volume restored" (R1.1-B W5, lane 3-B; US-R1F-20)

@MainActor
extension AudioViewModel {
    /// Whether the DSP rows work now (US-R1F-20 item 1): inert exactly while the path actually playing is Pure —
    /// Pure asked for while Enhanced plays (Bluetooth, a channel mismatch) leaves them live.
    var dspRowAvailability: DSPRowAvailability {
        DSPRowAvailability(pathIsPure: signalPath.path == .pure, pureRequested: pureModeEnabled)
    }

    /// "Leave Pure": the Pure switch off. It takes effect the way the switch always does — the next time a song is
    /// started (US-R1F-13) — and the rows say so until then.
    func leavePure() {
        pureModeEnabled = false
    }

    /// Pure gave the device's volume back at a level it was not at (`reportPureVolumeRestores`): say so, once.
    func pureVolumeRestored() {
        logUX("pure: the device's volume restored")
        volumeRestoredToast.show(Self.volumeRestoredMessage)
    }

    /// The toast's words (US-R1F-20 item 4).
    static let volumeRestoredMessage = "Volume restored"
}
