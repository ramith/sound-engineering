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
//   • "Keep playback on this device" ON (pinned): the app's device wins over the system default.
//     The app puts it back as the default while Enhanced plays and just before Enhanced starts, but
//     never while idle (connecting headphones for another app is not undone behind the user's back).
//     Pure plays on the device directly, so it needs no default.
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

    public init(target: UInt32, targetAlive: Bool, systemDefault: UInt32, playback: OutputPlayback, pinned: Bool) {
        self.target = target
        self.targetAlive = targetAlive
        self.systemDefault = systemDefault
        self.playback = playback
        self.pinned = pinned
    }
}

/// What the engine does about an event, in this order: pause, take the new target, put the
/// target back as the system default, restart the Enhanced engine. All false / nil = nothing.
public struct OutputDeviceAction: Sendable, Equatable, CustomStringConvertible {
    /// The device the app plays on went away during playback: stop, and say so (never carry on
    /// from another device).
    public internal(set) var pauseForDeviceLoss = false
    /// Make this device the app's device. The pill, the per-output EQ, the limiter ceiling and the
    /// crossfeed check all follow it.
    public internal(set) var adoptTarget: UInt32?
    /// Make the app's device the system default again (pinned, Enhanced playing or starting).
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
    public static func action(for event: OutputDeviceEvent, facts: OutputDeviceFacts) -> OutputDeviceAction {
        let starting = event == .enhancedStarting
        let playback = starting ? OutputPlayback.enhanced : facts.playback
        var action = OutputDeviceAction()
        guard facts.targetAlive else {
            // The device is gone. Playing → pause, never jump on. Pinned or not, a pin can't hold a
            // device that isn't there: the system default becomes the app's device.
            action.pauseForDeviceLoss = playback != .idle && !starting
            action.adoptTarget = defaultElsewhere(facts) ? facts.systemDefault : nil
            return action
        }
        if defaultElsewhere(facts) {
            if facts.pinned {
                // Enhanced plays on the system default, so it must be the app's device again.
                action.reassertTarget = playback == .enhanced
            } else {
                action.adoptTarget = facts.systemDefault
            }
        }
        // The Enhanced engine stops on a configuration change, and must follow an adopted device
        // even if no configuration change is posted. The start itself starts the engine.
        let engineMustMove = event == .engineReconfigured || action.adoptTarget != nil
        action.reestablishEnhanced = playback == .enhanced && !starting && engineMustMove
        return action
    }

    /// Whether playback must restart on the new output when the app's device changes (picked in
    /// the pill, or adopted by follow). The Enhanced engine follows the system default by itself;
    /// the Pure HAL engine is bound to its device, so it is restarted there at the playhead (Pure
    /// if the new device allows it, else Enhanced). Not after a lost device: that one pauses.
    public static func playbackMovesWithOutput(isPlaying: Bool, onPure: Bool, interrupted: Bool) -> Bool {
        isPlaying && onPure && !interrupted
    }

    /// The system default is a real device other than the app's.
    private static func defaultElsewhere(_ facts: OutputDeviceFacts) -> Bool {
        facts.systemDefault != 0 && facts.systemDefault != facts.target
    }
}
