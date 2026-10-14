// OutputDeviceSelection — the device the app plays on, and the device the user chose (R1, council N92).
//
// One field used to mean both. After a lost device the app adopted the fallback (the speakers), so the
// pin moved there too; when the headphones the user chose came back, Play put the speakers back as the
// system default and played on them. The two are kept apart here, and only the user moves the choice.

/// The output devices the app keeps, apart from the hardware's own state: the device it plays on (the
/// target), the device the user chose, and "Keep playback on this device". One value, read and written
/// whole, so the output rule never sees one without the others.
///
/// The target moves whenever the output rule adopts a device (`OutputDevicePolicy`): the system default
/// after a lost device or in follow mode, or the chosen device when it comes back. The choice moves only
/// by the user: a pick in the device menu (the device the app starts on counts as one), or turning the
/// switch on, which keeps the device in use. Playing on a fallback is not a pick. The choice is held by
/// UID (`kAudioDevicePropertyDeviceUID`): a reconnect can give a device a new id, never a new UID. It
/// lasts for the session (nothing persists it across launches yet).
public struct OutputDeviceSelection: Sendable, Equatable {
    /// The device the app plays on (0 = none).
    public private(set) var target: UInt32 = 0
    /// The UID of the device the user chose ("" = none yet).
    public private(set) var chosenUID = ""
    /// "Keep playback on this device" (on by default).
    public private(set) var pinned = true
    /// The target's UID, so that turning the switch on can choose it without asking CoreAudio.
    private var targetUID = ""

    public init() {}

    /// The user picked this device: the app plays on it, and the pin holds it from now on.
    public mutating func choose(_ device: UInt32, uid: String) {
        target = device
        targetUID = uid
        chosenUID = uid
    }

    /// The output rule moved the app to this device. The user's choice stays where it was.
    public mutating func adopt(_ device: UInt32, uid: String) {
        target = device
        targetUID = uid
    }

    /// The switch. Turning it on keeps the device in use ("this device"): it becomes the choice.
    public mutating func pin(_ isOn: Bool) {
        if isOn, !pinned {
            chosenUID = targetUID
        }
        pinned = isOn
    }
}
