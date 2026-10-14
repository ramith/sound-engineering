// OutputDevicePolicy — what the app does when its output device changes under it (Sprint G).
//
// The engine watches four things: the device list, the system default output, whether the device
// the app plays on is still alive, and the Enhanced engine's configuration changes. It also checks
// once more just before the Enhanced engine starts. Every one of those feeds the facts below into
// ONE rule, here, so each case is decided the same way and is unit-tested without CoreAudio.
//
// The founder's decisions this encodes:
//   • A disconnect PAUSES (commit 94b263c). When the device the app plays on goes away, playback
//     stops; nothing carries on from another device by itself.
//   • "Keep playback on this device" ON (pinned): the device the user CHOSE wins over the system
//     default. The app puts it back as the default while Enhanced plays and just before Enhanced
//     starts, but never while idle (connecting headphones for another app is not undone behind the
//     user's back). Pure plays on the device directly, so it needs no default.
//   • "Return to headphones" (R1, council N92): the pin holds the device the user chose, not the
//     fallback the app moved to when it went away (`OutputDeviceSelection`). While the chosen device
//     is away, the fallback is temporary: the app follows the system default as with the switch off,
//     and never puts a fallback back as the default. When the chosen device returns it is the app's
//     device again: the next Play plays on it, and playback that resumed on the fallback moves back.
//   • The device the app starts on is not a choice (R1): only a pick in the device menu, or turning
//     the switch on, is. Until then nothing is chosen, and pinned behaves exactly as follow.
//   • OFF (follow): the app takes the system default as its device, playing or not.

/// What the app is playing through when an output event arrives.
public enum OutputPlayback: Sendable, Equatable {
    /// Nothing is playing (stopped, paused, or paused for a lost device).
    case idle
    /// The Enhanced path: the `AVAudioEngine`, which plays on the system default output.
    case enhanced
    /// The Pure path: the HAL engine, which plays on the app's device directly.
    case pure
}

/// What happened to the output.
public enum OutputDeviceEvent: Sendable, Equatable {
    /// A device was added or removed (`kAudioHardwarePropertyDevices`).
    case devicesChanged
    /// The system default output changed (`kAudioHardwarePropertyDefaultOutputDevice`): the app
    /// changed it, or Control Center ▸ Sound, or a device that connected and took it.
    case defaultChanged
    /// The app's device reported a change of `kAudioDevicePropertyDeviceIsAlive`.
    case targetAliveChanged
    /// `AVAudioEngineConfigurationChange`: the Enhanced engine stopped and must be restarted to play on.
    case engineReconfigured
    /// The Enhanced engine is about to start playback.
    case enhancedStarting
}

/// The state the rule decides from, read fresh for every event.
public struct OutputDeviceFacts: Sendable, Equatable {
    /// The device the app plays on: the one picked in the app, or adopted (0 = none).
    public var target: UInt32
    /// Whether that device still exists and reports itself alive.
    public var targetAlive: Bool
    /// The system default output device (0 = none).
    public var systemDefault: UInt32
    /// What is playing right now.
    public var playback: OutputPlayback
    /// "Keep playback on this device".
    public var pinned: Bool
    /// The device the user chose (`OutputDeviceSelection`), when it is here to play on
    /// (`chosenDevice(_:alive:listed:)`): its id now, which a reconnect may have changed (0 = away,
    /// not ready yet, or none chosen).
    public var chosen: UInt32

    public init(
        target: UInt32,
        targetAlive: Bool,
        systemDefault: UInt32,
        playback: OutputPlayback,
        pinned: Bool,
        chosen: UInt32
    ) {
        self.target = target
        self.targetAlive = targetAlive
        self.systemDefault = systemDefault
        self.playback = playback
        self.pinned = pinned
        self.chosen = chosen
    }
}

/// What the engine does about an event, in this order: pause, take the new target, put the
/// target back as the system default, restart the Enhanced engine. All false / nil = nothing.
public struct OutputDeviceAction: Sendable, Equatable, CustomStringConvertible {
    /// The device the app plays on went away during playback: stop, and say so (never carry on
    /// from another device).
    public internal(set) var pauseForDeviceLoss = false
    /// Make this device the app's device: the system default (follow, a lost device, or the chosen
    /// device away), or the chosen device back. The pill, the per-output EQ, the limiter ceiling and
    /// the crossfeed check all follow it. Never 0.
    public internal(set) var adoptTarget: UInt32?
    /// Make the app's device — the adopted one, if any — the system default (pinned to the chosen
    /// device, Enhanced playing or starting). Only ever the chosen device: never a fallback, never 0.
    public internal(set) var reassertTarget = false
    /// Restart the stopped Enhanced engine and re-schedule from the playhead, on the target.
    public internal(set) var reestablishEnhanced = false

    public var description: String {
        var parts: [String] = []
        if pauseForDeviceLoss {
            parts.append("pause (device lost)")
        }
        if let adoptTarget {
            parts.append("adopt \(adoptTarget)")
        }
        if reassertTarget {
            parts.append("re-assert target as default")
        }
        if reestablishEnhanced {
            parts.append("re-establish Enhanced")
        }
        return parts.isEmpty ? "nothing" : parts.joined(separator: ", ")
    }
}

/// The rule. Pure: the same facts and event always give the same action.
public enum OutputDevicePolicy {
    /// Decide what to do about `event`, given `facts`.
    ///
    /// Guarantees the callers rely on:
    ///   • Converges. After the action, the same facts with the target adopted or re-asserted ask
    ///     for nothing more, so the app's own default changes cannot loop.
    ///   • `.enhancedStarting` never pauses and never restarts the engine (the start does that);
    ///     it only adopts a target or re-asserts one.
    ///   • Device 0 ("none") is never adopted, kept as alive, or re-asserted.
    public static func action(for event: OutputDeviceEvent, facts: OutputDeviceFacts) -> OutputDeviceAction {
        let starting = event == .enhancedStarting
        let playback = starting ? OutputPlayback.enhanced : facts.playback
        var action = OutputDeviceAction()
        // The device is gone (no device at all is never alive). Playing → pause, never jump on. A
        // start isn't playing yet: it plays on the new target below.
        let targetAlive = facts.targetAlive && facts.target != 0
        action.pauseForDeviceLoss = !targetAlive && playback != .idle && !starting
        let next = destination(facts)
        action.adoptTarget = next != facts.target ? next : nil
        // Enhanced plays on the system default, so it must be the chosen device again.
        action.reassertTarget = holdsChoice(facts) && playback == .enhanced && !action.pauseForDeviceLoss
            && facts.systemDefault != 0 && facts.systemDefault != next
        // The Enhanced engine stops on a configuration change, and must follow an adopted device
        // even if no configuration change is posted. The start itself starts the engine; a pause
        // restarts nothing.
        let engineMustMove = event == .engineReconfigured || action.adoptTarget != nil
        action.reestablishEnhanced = playback == .enhanced && !starting && !action.pauseForDeviceLoss
            && engineMustMove
        return action
    }

    /// The `chosen` fact for the device the chosen UID resolves to (`id`, 0 = none): that id when it
    /// is alive and the device menu lists it (`listed`, DeviceListPolicy). A Bluetooth device appears
    /// mid-handshake with no output stream, so it is not back until its output exists — the rule
    /// would otherwise make it the target, or the default, with nothing to play on.
    public static func chosenDevice(_ id: UInt32, alive: Bool, listed: Bool) -> UInt32 {
        alive && listed ? id : 0
    }

    /// Whether playback must restart on the new output when the app's device changes (picked in
    /// the pill, adopted by follow or after a loss, or the chosen device back). The Enhanced engine
    /// follows the system default by itself; the Pure HAL engine is bound to its device, so it is
    /// restarted there at the playhead (Pure if the new device allows it, else Enhanced). Not after
    /// a lost device: that one pauses.
    public static func playbackMovesWithOutput(isPlaying: Bool, onPure: Bool, interrupted: Bool) -> Bool {
        isPlaying && onPure && !interrupted
    }

    /// Where Play resumes after the engine paused for a lost device: a real pause, so the song's
    /// place is kept — the last playhead read while it played (the engine reports none once its
    /// device is gone), within the song. `nil` when nothing was playing: no pause, nothing to keep.
    /// Only Play resumes it; no device event ever does (pause on disconnect, never auto-jump).
    public static func resumeAfterDeviceLoss(isPlaying: Bool, lastPlayhead: Double, duration: Double) -> Double? {
        guard isPlaying else { return nil }
        let atLeastZero = lastPlayhead.isFinite ? max(lastPlayhead, 0) : 0
        return duration > 0 ? min(atLeastZero, duration) : atLeastZero
    }

    /// The device the app plays on after this event. Pinned with the chosen device here: that one,
    /// wherever it is (a reconnect may have moved its id). Otherwise — follow, or the chosen device
    /// away, so the target is a temporary fallback — the system default when it is a real device
    /// other than the target; a pin never holds a device the user did not choose. Else the target.
    private static func destination(_ facts: OutputDeviceFacts) -> UInt32 {
        if holdsChoice(facts) {
            return facts.chosen
        }
        let defaultElsewhere = facts.systemDefault != 0 && facts.systemDefault != facts.target
        return defaultElsewhere ? facts.systemDefault : facts.target
    }

    /// The pin is on and the device it holds is connected.
    private static func holdsChoice(_ facts: OutputDeviceFacts) -> Bool {
        facts.pinned && facts.chosen != 0
    }
}
