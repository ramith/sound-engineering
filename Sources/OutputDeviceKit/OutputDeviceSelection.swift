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
/// by the user: a pick in the device menu, or turning the switch on, which keeps the device in use. The
/// device the app starts on is not a choice (founder decision): until the user picks, there is none, and
/// the pin follows the system default exactly as the switch off does. Playing on a fallback is not a
/// pick either. The choice is held by UID (`kAudioDevicePropertyDeviceUID`): a reconnect can give a
/// device a new id, never a new UID. It outlives the session: the app keeps it with the listener's
/// settings and hands it back at launch (`restoreChoice`, DEV-1).
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

    /// A pick as `choose` made it, so that one the system refuses can be taken back (`undo`).
    public struct Pick: Sendable {
        let device: UInt32
        let uid: String
        let replacedTarget: UInt32
        let replacedTargetUID: String
        let replacedChosenUID: String
    }

    /// The user picked this device: the app plays on it, and the pin holds it from now on.
    @discardableResult
    public mutating func choose(_ device: UInt32, uid: String) -> Pick {
        let pick = Pick(device: device, uid: uid, replacedTarget: target, replacedTargetUID: targetUID,
                        replacedChosenUID: chosenUID)
        target = device
        targetUID = uid
        chosenUID = uid
        return pick
    }

    /// Take back a pick the system refused: only what it set, and only where it still stands. A move
    /// the output rule made in the meantime, or the switch, stays.
    public mutating func undo(_ pick: Pick) {
        if target == pick.device {
            target = pick.replacedTarget
            targetUID = pick.replacedTargetUID
        }
        if chosenUID == pick.uid {
            chosenUID = pick.replacedChosenUID
        }
    }

    /// The device the user chose before the last quit, by UID ("" = none), as the app kept it: the
    /// choice again, and nothing else — the target stays the device the app launched on until the
    /// output rule moves to the choice (`OutputDeviceEvent.choiceRestored`).
    public mutating func restoreChoice(uid: String) {
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
