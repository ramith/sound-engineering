// LevelingKit — what the decision builder reads of one track (R1.1-B W5, lane 3-A; the level-and-fold design,
// docs/design/level-and-fold/README.md §3, §4 and §S3).
//
// The Kit depends on no other target, so the app's boundary converts into these values: the analysis store's record
// (TrackLoudnessKit's `TrackAnalysis`) into a `LevelingTrack.Measurement` — with the LFE rule's verdict computed
// there by AudioDSP's `asFoldDecideLfe`, and each `TrackAnalysis.Profile` into a `CompactLoudnessProfile` — and the
// tag reader's raw values (TrackLoudnessKit's `TrackGainTags`) into a `GainTags`.

import Foundation

/// The listener's Leveling setting (US-R1F-10 item 1). Off is the faithful default (FD-2). The raw values are the
/// setting's stored form.
public enum LevelingMode: String, Sendable, CaseIterable {
    /// No leveling gain. The fold's trim still applies (a surround file on a stereo output), so an Off decision
    /// still carries the track's measured peaks.
    case off
    /// The album's level when the neighbouring track (the one just played, or the next) is from the same album;
    /// otherwise the track's own (founder, 2026-10-26).
    case auto
    /// The album's level: its loudest song at −18 LUFS (founder, 2026-10-26).
    case album
    /// Each track at its own level; a run of tracks that join without a pause shares the level of the run's own
    /// loudest member (founder, 2026-10-30) — when they play in album order, the only order in which they join.
    case track
}

/// The fold's LFE variants, as the analysis measures them and the planner plays them: TrackPlanBridge.h's
/// `AsLfeVariant` table (the per-side gain in brackets). The numbers are the C table's indices.
public enum LfeVariant: Int, Sendable, CaseIterable {
    /// The LFE left out (0).
    case omit = 0
    /// The music-disc convention, −6 dB per side (0.5).
    case music = 1
    /// Full level per side (1.0).
    case full = 2
    /// The film convention, +4 dB per side (1.585).
    case film = 3
}

/// What the decision builder knows of one track: its album, our own analysis of it, and its gain tags.
public struct LevelingTrack: Sendable, Equatable {
    /// What the one analysis pass measured (TrackLoudnessKit's `TrackAnalysis`, current version only), in the
    /// decision builder's terms.
    public struct Measurement: Sendable, Equatable {
        /// L_N: integrated loudness as decoded (LUFS); nil when no block passed the gates (silence, or under
        /// 0.4 s).
        public var loudness: Double?
        /// TP_N: the true peak over every channel, the LFE included (dBTP).
        public var truePeak: Double?
        /// The rate the true peaks were measured at (the engine's).
        public var peakRate: Double
        /// The channel roles the numbers were measured with (`AsChannelRole` values).
        public var roles: [UInt8]
        /// The track's length as decoded (seconds).
        public var durationSeconds: Double
        /// The first and last whole 400 ms block's loudness (LUFS; −200 for digital silence; nil when the track is
        /// shorter than one block). The continuity judge reads them.
        public var headLoudness: Double?
        public var tailLoudness: Double?
        /// The stereo fold's numbers; nil when the file does not fold (two channels or fewer).
        public var folded: Folded?
        /// The saved −ΔL profiles the boundary loaded for this track (any subset of its bases). The decision keeps
        /// the ones its fold variant plays (`TrackLevelingDecision.profileBases`).
        public var profiles: [CompactLoudnessProfile]

        public init(loudness: Double?, truePeak: Double?, peakRate: Double, roles: [UInt8], durationSeconds: Double,
                    headLoudness: Double?, tailLoudness: Double?, folded: Folded?,
                    profiles: [CompactLoudnessProfile] = []) {
            self.loudness = loudness
            self.truePeak = truePeak
            self.peakRate = peakRate
            self.roles = roles
            self.durationSeconds = durationSeconds
            self.headLoudness = headLoudness
            self.tailLoudness = tailLoudness
            self.folded = folded
            self.profiles = profiles
        }
    }

    /// The BS.775 stereo fold's numbers, one per `LfeVariant`, and the LFE rule's verdict.
    public struct Folded: Sendable, Equatable {
        /// L_F[v] (LUFS); nil where nothing passed the gates.
        public var loudness: [Double?]
        /// TP_F[v] (dBTP).
        public var truePeak: [Double?]
        /// Whether the LFE rule includes the LFE (`asFoldDecideLfe` → `asLfeVerdictIncludes`, at the boundary).
        /// False for a fold with no LFE channel.
        public var lfeIncludes: Bool

        public init(loudness: [Double?], truePeak: [Double?], lfeIncludes: Bool) {
            self.loudness = loudness
            self.truePeak = truePeak
            self.lfeIncludes = lfeIncludes
        }
    }

    /// The library's album id. Nil for a loose file, or a song with no album title: such a track is never "the
    /// same album" as another (plan check §6, Auto rule (4) and (8)).
    public var album: Int64?
    /// Our own analysis; nil while the track is not analysed (or its record is of another version).
    public var measurement: Measurement?
    /// The file's ReplayGain 2.0 / EBU R128 tags; nil when none were read. Used only while the track is not
    /// analysed (US-R1F-10 item 4).
    public var tags: GainTags?

    public init(album: Int64?, measurement: Measurement? = nil, tags: GainTags? = nil) {
        self.album = album
        self.measurement = measurement
        self.tags = tags
    }
}

/// A file's loudness tags, as written: ReplayGain 2.0 (`REPLAYGAIN_TRACK_GAIN` and the rest, relative to −18 LUFS,
/// peaks as linear sample values) and EBU R128 (`R128_TRACK_GAIN` / `R128_ALBUM_GAIN`, Q7.8 dB relative to
/// −23 LUFS). The conversion to the −18 LUFS target is this Kit's rule (`trackLevel`, `albumLevel`).
public struct GainTags: Sendable, Equatable {
    /// The loudness and sample peak a tag pair says, in the decision's terms.
    public struct Level: Sendable, Equatable {
        /// The integrated loudness the tag implies (LUFS).
        public var loudness: Double
        /// The tag's sample peak (dBFS); nil when the file carries none.
        public var peak: Double?

        public init(loudness: Double, peak: Double?) {
            self.loudness = loudness
            self.peak = peak
        }
    }

    /// `REPLAYGAIN_TRACK_GAIN` (dB).
    public var replayGainTrack: Double?
    /// `REPLAYGAIN_TRACK_PEAK` (linear, 1.0 = full scale).
    public var replayGainTrackPeak: Double?
    /// `REPLAYGAIN_ALBUM_GAIN` (dB).
    public var replayGainAlbum: Double?
    /// `REPLAYGAIN_ALBUM_PEAK` (linear).
    public var replayGainAlbumPeak: Double?
    /// `R128_TRACK_GAIN` (Q7.8: 1/256 dB).
    public var r128Track: Int?
    /// `R128_ALBUM_GAIN` (Q7.8).
    public var r128Album: Int?

    public init(replayGainTrack: Double? = nil, replayGainTrackPeak: Double? = nil, replayGainAlbum: Double? = nil,
                replayGainAlbumPeak: Double? = nil, r128Track: Int? = nil, r128Album: Int? = nil) {
        self.replayGainTrack = replayGainTrack
        self.replayGainTrackPeak = replayGainTrackPeak
        self.replayGainAlbum = replayGainAlbum
        self.replayGainAlbumPeak = replayGainAlbumPeak
        self.r128Track = r128Track
        self.r128Album = r128Album
    }

    /// ReplayGain 2.0's reference: a gain of 0 dB means the track sits at −18 LUFS.
    public static let replayGainReferenceLufs = -18.0
    /// EBU R128's reference for its gain tags: −23 LUFS.
    public static let r128ReferenceLufs = -23.0
    /// The loudness a tag may imply: from BS.1770's absolute gate (−70 LUFS, below which there is no programme) to
    /// 0 LUFS (a full-scale stereo sine; no real master is louder). A tag outside it is wrong and is ignored — 9d's
    /// track gain of −20 dB would say +2 LUFS and play the track 20 dB down.
    public static let plausibleLoudness = -70.0 ... 0.0

    /// The track's own level by its tags (ReplayGain 2.0 first, then R128); nil when it has none, or only an
    /// implausible one.
    public var trackLevel: Level? {
        Self.level(replayGain: replayGainTrack, peak: replayGainTrackPeak, r128: r128Track)
    }

    /// The album's level by this track's album tags; nil when it has none, or only an implausible one.
    public var albumLevel: Level? {
        Self.level(replayGain: replayGainAlbum, peak: replayGainAlbumPeak, r128: r128Album)
    }

    /// A gain tag's level: the loudness it implies (its reference minus the gain), with a ReplayGain peak in dBFS.
    private static func level(replayGain: Double?, peak: Double?, r128: Int?) -> Level? {
        let loudness: Double? = if let replayGain {
            replayGainReferenceLufs - replayGain
        } else if let r128 {
            r128ReferenceLufs - Double(r128) / 256
        } else {
            nil
        }
        guard let loudness, loudness.isFinite, plausibleLoudness.contains(loudness) else { return nil }
        let peakDbfs = (replayGain != nil) ? peak.flatMap { $0 > 0 && $0.isFinite ? 20 * log10($0) : nil } : nil
        return Level(loudness: loudness, peak: peakDbfs)
    }
}
