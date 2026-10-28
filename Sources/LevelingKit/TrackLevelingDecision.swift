// LevelingKit — the leveling decision (R1.1-B, the level-and-fold design, docs/design/level-and-fold/README.md §S3).
//
// Created at the coordinator's commit 0 of W4 holding only the decision (§9, condition C3.5). Lane 1 owns this
// file in W4: it completes the numbers the planner needs (with C2's saved −ΔL profile key) and their C-ABI
// mirror. Lane 3 adds the rules in W5: Auto, the sources, the album anchor and completeness, continuity, groups.

/// What the engine needs to level one track when it becomes audible: measured numbers only, already resolved
/// to their scope (the track, or its group's or album's anchor and maxima). It holds no ceiling rule and no
/// working ceiling; the C++ planner applies those against the output. It travels with the request that makes
/// its track audible (`startAudio(…, leveling:)`, `setNextTrack(…, leveling:)`).
public struct TrackLevelingDecision: Sendable, Equatable {
    public enum Mode: Sendable, Equatable { case off, leveled, unknownCut }
    public enum Source: Sendable, Equatable { case analysis, tags, unknownCut }

    /// Integrated loudness and true peak of the programme as decoded, all N channels; `nil` = unknown.
    public struct LevelNumbers: Sendable, Equatable {
        public var loudness: Double? // L, LUFS
        public var truePeak: Double? // TP_N, dBTP

        public init(loudness: Double?, truePeak: Double?) {
            self.loudness = loudness
            self.truePeak = truePeak
        }
    }

    /// The same on the BS.775 stereo fold, one value per LFE variant, and the variant the LFE rule chose.
    public struct FoldedNumbers: Sendable, Equatable {
        public var loudness: [Double] // L_F[v], LUFS
        public var truePeak: [Double] // TP_F[v], dBTP
        public var variant: Int // v

        public init(loudness: [Double], truePeak: [Double], variant: Int) {
            self.loudness = loudness
            self.truePeak = truePeak
            self.variant = variant
        }
    }

    public var mode: Mode
    public var source: Source
    /// The one continuity judge's verdict (§4): this track continues the previous one across a seam.
    public var continuousWithPrevious: Bool
    public var unfolded: LevelNumbers
    public var folded: FoldedNumbers?
    /// The channel roles the numbers were measured with; they must equal playback's, else the fallback trim.
    public var roles: [UInt8]

    public init(
        mode: Mode, source: Source, continuousWithPrevious: Bool,
        unfolded: LevelNumbers, folded: FoldedNumbers?, roles: [UInt8]
    ) {
        self.mode = mode
        self.source = source
        self.continuousWithPrevious = continuousWithPrevious
        self.unfolded = unfolded
        self.folded = folded
        self.roles = roles
    }
}
