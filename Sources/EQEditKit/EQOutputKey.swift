// EQOutputKey — an output device as the EQ remembers it (Sprint EQ, DEV-UID; review F4/F5).
// The EQ's per-output memory is keyed by the device's persistent UID, never by its
// AudioDeviceID (reassigned per session); the model UID is kept as the fallback that recognises
// another unit of the same model, and the name for display only.

public struct EQOutputKey: Hashable, Codable, Sendable {
    /// The device's persistent UID (`kAudioDevicePropertyDeviceUID`): the output's identity.
    public let uid: String

    /// The device's model UID (`kAudioDevicePropertyModelUID`), shared by every unit of the same
    /// model; `nil` when the device reports none.
    public let modelUID: String?

    /// The device's name, for display only (a rename keeps the same output).
    public let name: String

    public init(uid: String, modelUID: String?, name: String) {
        self.uid = uid
        self.modelUID = modelUID
        self.name = name
    }

    /// Whether going from `old` to `new` is a change of OUTPUT: a different UID, or an output
    /// appearing or going away. A re-read of the same output never counts — a new sample rate or
    /// buffer size, a rename, a model UID read differently — so the EQ's per-output memory
    /// switches only when the sound really moves to another device.
    public static func isOutputChange(from old: EQOutputKey?, to new: EQOutputKey?) -> Bool {
        old?.uid != new?.uid
    }

    /// The UID prefix of the private aggregate CoreAudio builds around the default device for one
    /// process (`CADefaultDeviceAggregate-<pid>-<n>`).
    private static let privateAggregatePrefix = "CADefaultDeviceAggregate-"

    /// Whether this output can have a slot of its own: it has a UID, and not one that changes every
    /// launch — a process-private default-device aggregate is rebuilt under a new UID each run, so
    /// a slot pinned to it could never be found again. Such an output plays the shared slot.
    var isPinnable: Bool {
        !uid.isEmpty && !uid.hasPrefix(Self.privateAggregatePrefix)
    }
}
