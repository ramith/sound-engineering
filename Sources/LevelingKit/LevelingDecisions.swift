// LevelingKit — the decision builder (R1.1-B W5, lane 3-A; level-and-fold §3, §4, §S3; US-R1F-10 items 1–8, 18).
//
// One pure function turns what is known of a track and its neighbours into the decision that travels with the
// request that makes it audible (`startAudio(…, leveling:)`, `setNextTrack(…, leveling:)`, and
// `applyLevelingChange(current:next:)` on a mode change). It resolves the SCOPE (the track, its continuous run, or
// its album), the SOURCE (our analysis, then the file's tags, then the unknown cut) and the CONTINUITY verdict (the
// one judge, `LevelingRules.continuous`), and hands the planner measured numbers only: the gain, the cap and the
// fold's trim are the C++ planner's (`asPlanTrack`).

/// Everything the decision builder reads: the tracks it may be asked about, with their album-mates, by key, and
/// each album's running order. The coordinator assembles it off the main thread for the queue's horizon — from
/// the analysis store, the tag reader and the library's album reads — and keeps it as a value.
public struct LevelingLibrary: Sendable, Equatable {
    /// Each known track by its key: the file's standardized path (TrackLoudnessKit's `TrackIdentity.path`), the
    /// same string for the same file everywhere.
    public var tracks: [String: LevelingTrack]
    /// Each album's members in album order (disc, then track number), by key.
    public var albums: [Int64: [String]]

    public init(tracks: [String: LevelingTrack] = [:], albums: [Int64: [String]] = [:]) {
        self.tracks = tracks
        self.albums = albums
    }

    /// The decision for `request`'s track. A track the library does not know plays as unknown (−5 dB in a
    /// leveling mode; Off as Off).
    public func decision(for _: LevelingRequest) -> TrackLevelingDecision {
        .off // lane 3-A's rules replace this stub
    }
}

/// One question to the decision builder: which track, in which mode, between which neighbours.
public struct LevelingRequest: Sendable, Equatable {
    /// The track's key (`LevelingLibrary.tracks`).
    public var key: String
    /// The listener's setting.
    public var mode: LevelingMode
    /// The track heard just before this one: at a seam, the one it follows; at a fresh start, the one played last
    /// in this session, if any. Auto reads it ("the one just played"); continuity reads it at a seam.
    public var previous: String?
    /// The track queued to play after this one, in play order (shuffle's permutation included), if any.
    public var next: String?
    /// Whether this track becomes audible at a seam after `previous` (an armed pick) rather than by a fresh start.
    /// Only a seam can be continuous.
    public var atSeam: Bool
    /// The decision `previous` is playing with (the audible one, after any mode change). At a continuous seam the
    /// track inherits its numbers, so the level never steps there (US-R1F-10 item 18).
    public var previousDecision: TrackLevelingDecision?

    public init(key: String, mode: LevelingMode, previous: String? = nil, next: String? = nil, atSeam: Bool = false,
                previousDecision: TrackLevelingDecision? = nil) {
        self.key = key
        self.mode = mode
        self.previous = previous
        self.next = next
        self.atSeam = atSeam
        self.previousDecision = previousDecision
    }
}

/// The rules' named numbers (one place each; the founder's listen changes `lfeIncludeVariant` in one line).
public enum LevelingRules {
    /// The fold's LFE level when the LFE rule includes it: −6 dB per side, the design's recommendation for music
    /// discs (§12 F-3). The founder's two-album listen decides it.
    public static let lfeIncludeVariant = LfeVariant.music
    /// A member shorter than this is left out of an album's or a run's anchor (§3, the outlier guard), unless every
    /// member is.
    public static let anchorMinimumSeconds = 30.0

    /// The one continuity judge (§4): whether a track whose last block reads `tail` runs on into one whose first
    /// block reads `head` (LUFS; nil = unknown, which counts as sounding). Lane 3-A's rule (stub until it lands).
    public static func continuous(tail _: Double?, head _: Double?) -> Bool {
        true
    }
}

public extension TrackLevelingDecision {
    /// The saved −ΔL profiles this decision plays on: as decoded, and the fold at its variant when it folds. The
    /// coordinator loads these from the store (`TrackAnalysisStore.profiles(for:bases:)`) for the tracks it
    /// starts or arms; the builder keeps exactly these from a measurement's profiles.
    var profileBases: [CompactLoudnessProfile.Basis] {
        guard let folded else { return [.decoded] }
        return [.decoded, .fold(lfeVariant: folded.variant)]
    }
}
