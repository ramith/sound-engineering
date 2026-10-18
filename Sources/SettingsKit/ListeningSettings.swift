// ListeningSettings — what the app remembers of how the listener plays (R1.1-A, founder decision FD-2;
// council C-102, C-12, DEV-1): one typed value, kept whole by `SettingsStore`.
//
// A NEW INSTALL PLAYS FAITHFULLY. Every default here is the music as it was recorded: Pure off, Master
// Gain at unity, crossfeed off, the queue in order, nothing repeated — and FFmpeg, an in-process parser
// for files from anywhere, off (founder decision FD-3). Two things the app also starts
// faithfully are not kept here: Intensity, hidden and held at 0 until its effects are real (S17), so
// never restored; and the EQ, which keeps its own per-output memory (`EQStore`, `eqStateV2`) and starts
// Off on a new install.
//
// A BAD VALUE IS THE FAITHFUL DEFAULT, field by field: a value of the wrong type or out of range reads
// as that field's default, and the rest still read (a later build's added fields are simply ignored).
// The one exception is Master Gain, which is NEVER RESTORED LOUDER THAN IT WAS LEFT (C-102, hearing
// safety): Master Gain resets to unity — the loudest — so a level that can't be read, one that isn't
// there (version 1 always writes it, so its absence is damage), or one above unity (the law is turn-down
// only, so it was never left there) comes back Silent, the law's own safe reading of a bad value. The
// listener sees "Silent" and turns it up. A stored value that isn't readable settings at all reads
// `.unreadable`, Silent too (`SettingsStore.load`).

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
    /// "Use FFmpeg for other formats": FFmpeg may read a file Apple's decoder can't (R1.1-A, FD-3).
    /// Off by default.
    public var useFFmpeg: Bool
    /// The output devices whose own volume Pure turned down and has not yet put back
    /// (`MasterGainOnPure.allLoans`) — kept, so a crash or a device that went away gets its level back
    /// at the next launch. Empty on a new install, and whenever nothing is lowered.
    public var pureVolumeLoans: [PureVolumeLoan]

    /// Settings as given; every default is the faithful one (`faithful`).
    public init(
        pureMode: Bool = false,
        masterGainDecibels: Float = MasterGainLaw.unity,
        crossfeed: Bool = false,
        crossfeedStrength: CrossfeedStrength = .defaultStrength,
        shuffle: Bool = false,
        repeatMode: Int = 0,
        keepPlaybackOnDevice: Bool = true,
        chosenOutputUID: String? = nil,
        useFFmpeg: Bool = false,
        pureVolumeLoans: [PureVolumeLoan] = []
    ) {
        self.pureMode = pureMode
        self.masterGainDecibels = masterGainDecibels
        self.crossfeed = crossfeed
        self.crossfeedStrength = crossfeedStrength
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        self.keepPlaybackOnDevice = keepPlaybackOnDevice
        self.chosenOutputUID = chosenOutputUID
        self.useFFmpeg = useFFmpeg
        self.pureVolumeLoans = pureVolumeLoans
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

    /// The kept loans, read one by one (SET-3): one that can't be read, or a damaged one (not
    /// `PureVolumeLoan.isSound`), is dropped on its own — every other is a device still turned down.
    static func soundLoans(_ stored: [Lenient<PureVolumeLoan>]?) -> [PureVolumeLoan] {
        (stored ?? []).compactMap(\.value).filter(\.isSound)
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
        case keepPlaybackOnDevice, chosenOutputUID, useFFmpeg, pureVolumeLoans
    }

    /// The format this build writes.
    private static let version = 1

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let faithful = Self.faithful
        self.init(
            pureMode: container.field(.pureMode) ?? faithful.pureMode,
            masterGainDecibels: Self.restoredLevel(container.field(.masterGainDecibels)), // absent: Silent
            crossfeed: container.field(.crossfeed) ?? faithful.crossfeed,
            crossfeedStrength: container.field(.crossfeedStrength).flatMap(CrossfeedStrength.init(rawValue:))
                ?? faithful.crossfeedStrength,
            shuffle: container.field(.shuffle) ?? faithful.shuffle,
            repeatMode: Self.validRepeatMode(container.field(.repeatMode)),
            keepPlaybackOnDevice: container.field(.keepPlaybackOnDevice) ?? faithful.keepPlaybackOnDevice,
            chosenOutputUID: container.field(.chosenOutputUID).flatMap { (uid: String) in uid.isEmpty ? nil : uid },
            useFFmpeg: container.field(.useFFmpeg) ?? faithful.useFFmpeg,
            pureVolumeLoans: Self.soundLoans(container.field(.pureVolumeLoans))
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
        try container.encode(useFFmpeg, forKey: .useFFmpeg)
        try container.encode(pureVolumeLoans, forKey: .pureVolumeLoans)
    }
}

/// One element of a stored array, read on its own: a bad one is nil, and the array still reads.
struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) {
        value = try? Value(from: decoder)
    }
}

private extension KeyedDecodingContainer {
    /// The value stored under `key`, or `nil` when it is missing or isn't a `T`: one bad field never
    /// costs the others.
    func field<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
}
