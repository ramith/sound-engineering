import OutputDeviceKit

// MARK: - The output world the device scenarios run in

/// CoreAudio as the scenarios need it — which devices are connected (id → UID), which have no output
/// stream yet, and the system default — with the app's real output state (`OutputDeviceSelection`)
/// and its real rule (`OutputDevicePolicy`) on top. The few lines that read the facts and apply an
/// action do what the bridge does (`AudioEngineBridge+OutputDeviceMonitor`): an adopt moves the
/// target only, a re-assert makes the (new) target the default, a pause stops what plays.
struct OutputWorld {
    /// Connected, alive devices: id → UID.
    var devices: [UInt32: String]
    var systemDefault: UInt32
    /// Connected devices with no output stream yet (a Bluetooth device mid-handshake): the device
    /// menu doesn't list them.
    var notReady: Set<UInt32> = []
    var selection = OutputDeviceSelection()
    var playback = OutputPlayback.idle

    /// Where the sound comes out: Enhanced plays on the system default, Pure on the app's device.
    var soundsOn: UInt32 {
        switch playback {
        case .idle: 0
        case .enhanced: systemDefault
        case .pure: selection.target
        }
    }

    /// The UID of the device the user chose, as the selection holds it.
    var chosenUID: String {
        selection.chosenUID
    }

    /// The facts, read as the bridge reads them: the chosen device found by its UID among the
    /// connected devices, whatever its id is now, and taken only when it is ready to play on.
    func facts() -> OutputDeviceFacts {
        let resolved = devices.first { $0.value == selection.chosenUID }?.key ?? 0
        let chosen = OutputDevicePolicy.chosenDevice(resolved, alive: devices[resolved] != nil,
                                                     listed: !notReady.contains(resolved))
        return OutputDeviceFacts(
            target: selection.target, targetAlive: devices[selection.target] != nil,
            systemDefault: systemDefault, playback: playback, pinned: selection.pinned, chosen: chosen
        )
    }

    /// One output event through the rule, acted on as the bridge acts on it.
    @discardableResult
    mutating func handle(_ event: OutputDeviceEvent) -> OutputDeviceAction {
        let action = OutputDevicePolicy.action(for: event, facts: facts())
        if action.pauseForDeviceLoss {
            playback = .idle
        }
        if let adopted = action.adoptTarget {
            selection.adopt(adopted, uid: devices[adopted] ?? "")
        }
        if action.reassertTarget {
            systemDefault = selection.target
        }
        return action
    }

    /// The events macOS posts after a device change, in turn. Returns their actions.
    @discardableResult
    mutating func settle() -> [OutputDeviceAction] {
        [OutputDeviceEvent.targetAliveChanged, .devicesChanged, .defaultChanged].map { handle($0) }
    }

    /// The app starts — or re-initializes — on the system default (`initialize`): an adopt, never a
    /// choice.
    mutating func start() {
        playback = .idle
        selection.adopt(systemDefault, uid: devices[systemDefault] ?? "")
    }

    /// The user picks `device` in the menu (`selectDevice`): the target and the choice, then the default.
    mutating func pick(_ device: UInt32) {
        selection.choose(device, uid: devices[device] ?? "")
        systemDefault = device
    }

    /// The user presses Play on Enhanced: the start aligns the output, then the engine plays.
    @discardableResult
    mutating func playEnhanced() -> OutputDeviceAction {
        let action = handle(.enhancedStarting)
        playback = .enhanced
        return action
    }

    /// The user presses Play on Pure: the HAL engine opens the app's device directly.
    mutating func playPure() {
        playback = .pure
    }

    /// A device goes away; macOS moves the default to `newDefault`.
    mutating func disconnect(_ device: UInt32, defaultMovesTo newDefault: UInt32) {
        devices[device] = nil
        systemDefault = newDefault
    }

    /// A device connects (perhaps under a new id, perhaps before its output exists) and, usually,
    /// takes the default.
    mutating func connect(_ device: UInt32, uid: String, takesDefault: Bool, outputReady: Bool = true) {
        devices[device] = uid
        if !outputReady {
            notReady.insert(device)
        }
        if takesDefault {
            systemDefault = device
        }
    }

    /// A connected device's output stream appears (its Bluetooth handshake is done).
    mutating func outputAppears(_ device: UInt32) {
        notReady.remove(device)
    }
}
