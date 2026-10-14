// ListeningSettings — what the app remembers of how the listener plays (R1.1-A, founder decision FD-2;
// council C-102, C-12, DEV-1): one typed value, kept whole by `SettingsStore`.
//
// A NEW INSTALL PLAYS FAITHFULLY. Every default here is the music as it was recorded: Pure off, Master
// Gain at unity, crossfeed off, the queue in order, nothing repeated. Two things the app also starts
// faithfully are not kept here: Intensity, hidden and held at 0 until its effects are real (S17), so
// never restored; and the EQ, which keeps its own per-output memory (`EQStore`, `eqStateV2`) and starts
// Off on a new install.
//
// A BAD VALUE IS THE FAITHFUL DEFAULT, field by field: a value of the wrong type or out of range reads
// as that field's default, and the rest still read (a later build's added fields are simply ignored).
// The one exception is Master Gain, which is NEVER RESTORED LOUDER THAN IT WAS LEFT (C-102, hearing
// safety): Master Gain resets to unity — the loudest — so a level that can't be read, or one above
// unity (the law is turn-down only, so it was never left there), comes back Silent, the law's own safe
// reading of a bad value. The listener sees "Silent" and turns it up.

import EQEditKit
import Foundation

public struct ListeningSettings: Equatable, Sendable {
    /// Pure Mode, as the listener asked for it (it engages at the next start the device allows).
    public var pureMode: Bool
    /// Master Gain as it was left, in dB (`MasterGainLaw`: unity at most, −∞ for Silent).
    public var masterGainDecibels: Float
    /// Crossfeed, as the listener chose it — not as the output allows it: it plays on headphones only,
    /// and an output that holds it off doesn't switch the choice off.
    public var crossfeed: Bool
    /// The crossfeed strength chosen.
    public var crossfeedStrength: CrossfeedStrength
    /// Shuffle.
    public var shuffle: Bool
    /// Repeat: 0 off, 1 all, 2 one (`AudioViewModel.repeatMode`).
    public var repeatMode: Int
    /// "Keep playback on this device".
    public var keepPlaybackOnDevice: Bool
    /// The UID of the output device the user chose (a pick, or turning "Keep playback on this device"
    /// on), `nil` when none is chosen. The device the app launches on is never a choice.
    public var chosenOutputUID: String?

    /// Settings as given; every default is the faithful one (`faithful`).
    public init(
        pureMode: Bool = false,
        masterGainDecibels: Float = MasterGainLaw.unity,
        crossfeed: Bool = false,
        crossfeedStrength: CrossfeedStrength = .defaultStrength,
        shuffle: Bool = false,
        repeatMode: Int = 0,
        keepPlaybackOnDevice: Bool = true,
        chosenOutputUID: String? = nil
    ) {
        self.pureMode = pureMode
        self.masterGainDecibels = masterGainDecibels
        self.crossfeed = crossfeed
        self.crossfeedStrength = crossfeedStrength
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        self.keepPlaybackOnDevice = keepPlaybackOnDevice
        self.chosenOutputUID = chosenOutputUID
    }

    /// A new install: the music as it was recorded.
    static let faithful = ListeningSettings()

    /// A stored value that can't be read at all: the faithful default, with Master Gain Silent —
    /// whatever level was left is unknown, and it must not come back louder.
    static let unreadable = ListeningSettings(masterGainDecibels: -.infinity)

    /// Master Gain as stored, never louder than it was left: a level at or below unity as it is; one
    /// above unity, or no level at all (`nil`, NaN), Silent.
    static func restoredLevel(_ stored: Float?) -> Float {
        guard let stored, stored <= MasterGainLaw.unity else { return -.infinity }
        return stored
    }

    /// A stored repeat mode, or off when it isn't one.
    static func validRepeatMode(_ stored: Int?) -> Int {
        guard let stored, (0 ... 2).contains(stored) else { return 0 }
        return stored
    }
}

// MARK: - Stored form

/// One JSON object, its version inside as well as in its key (`listeningSettingsV1`), the way the EQ
/// keeps `eqStateV2`. Silent is −∞, which JSON has no number for: the coders write it as a string.
extension ListeningSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, pureMode, masterGainDecibels, crossfeed, crossfeedStrength, shuffle, repeatMode
        case keepPlaybackOnDevice, chosenOutputUID
    }

    /// The format this build writes.
    private static let version = 1

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let faithful = Self.faithful
        self.init(
            pureMode: container.field(.pureMode) ?? faithful.pureMode,
            masterGainDecibels: container.contains(.masterGainDecibels)
                ? Self.restoredLevel(container.field(.masterGainDecibels))
                : faithful.masterGainDecibels,
            crossfeed: container.field(.crossfeed) ?? faithful.crossfeed,
            crossfeedStrength: container.field(.crossfeedStrength).flatMap(CrossfeedStrength.init(rawValue:))
                ?? faithful.crossfeedStrength,
            shuffle: container.field(.shuffle) ?? faithful.shuffle,
            repeatMode: Self.validRepeatMode(container.field(.repeatMode)),
            keepPlaybackOnDevice: container.field(.keepPlaybackOnDevice) ?? faithful.keepPlaybackOnDevice,
            chosenOutputUID: container.field(.chosenOutputUID).flatMap { (uid: String) in uid.isEmpty ? nil : uid }
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.version, forKey: .version)
        try container.encode(pureMode, forKey: .pureMode)
        try container.encode(masterGainDecibels, forKey: .masterGainDecibels)
        try container.encode(crossfeed, forKey: .crossfeed)
        try container.encode(crossfeedStrength.rawValue, forKey: .crossfeedStrength)
        try container.encode(shuffle, forKey: .shuffle)
        try container.encode(repeatMode, forKey: .repeatMode)
        try container.encode(keepPlaybackOnDevice, forKey: .keepPlaybackOnDevice)
        try container.encodeIfPresent(chosenOutputUID, forKey: .chosenOutputUID)
    }
}

private extension KeyedDecodingContainer {
    /// The value stored under `key`, or `nil` when it is missing or isn't a `T`: one bad field never
    /// costs the others.
    func field<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}
