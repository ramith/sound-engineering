import CoreAudio
import SettingsKit

// MARK: - AudioViewModel: the DSP rows in Pure, and "Volume restored" (R1.1-B W5, lane 3-B; US-R1F-20)

@MainActor
extension AudioViewModel {
    /// Whether the DSP rows work now (US-R1F-20 item 1): inert exactly while the path in use is Pure — Pure asked
    /// for while Enhanced plays (Bluetooth, a channel mismatch) leaves them live. A pause or a stop never changes
    /// them: they keep the path that last played (`SignalPathInfo.playedPath`). Before anything has played since
    /// launch they follow what a start would do on this device: Pure chosen on an output that can play bit-perfect
    /// → inert (founder's decisions, 2026-10-30).
    var dspRowAvailability: DSPRowAvailability {
        let pathIsPure = signalPath.playedPath.map { $0 == .pure }
            ?? (pureModeEnabled && selectedDevice.map(Self.takesPure) == true)
        return DSPRowAvailability(pathIsPure: pathIsPure, pureRequested: pureModeEnabled)
    }

    /// Whether Pure plays on `device`, as far as the device decides it before any file: not over Bluetooth or
    /// AirPlay (a codec below the HAL) and not on a virtual or aggregate device (no exclusive hardware path) — the
    /// device half of the engine's own rule (`CoreAudioDevice.cpp`'s `isLossyWireless` / `isVirtualOrAggregate`,
    /// by transport). The file's half (its rate, its channels) is only known at the start.
    private static func takesPure(_ device: AudioDeviceModel) -> Bool {
        ![kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE, kAudioDeviceTransportTypeAirPlay,
          kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate,
          kAudioDeviceTransportTypeAutoAggregate].contains(device.transportType)
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
