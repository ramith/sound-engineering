// LevelingKit — the leveling decision (R1.1-B, the level-and-fold design, docs/design/level-and-fold/README.md §S3).
//
// Created at the coordinator's commit 0 of W4 holding only the decision (§9, condition C3.5). Lane 1 owns this
// file in W4: it completes the numbers the planner needs (with C2's saved −ΔL profiles); their C-ABI mirror is the
// app's (`AsTrackLeveling`, built in `AudioEngineBridge+Leveling.swift`, since this Kit imports nothing). Lane 3 adds
// the rules in W5: Auto, the sources, the album anchor and completeness, continuity, groups.

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
    /// The rate the true peaks were measured at (the analysis runs at the engine's rate); `nil` when not known (a
    /// tag's peak). A peak measured at another rate than the engine's counts as unknown, raised to it above 0 dBTP.
    public var peakRate: Double?
    /// The saved compact −ΔL profiles of the bases this track can play on (C2): as decoded, and the fold at the
    /// decision's variant. Empty when none is saved yet (a never-analysed first play profiles as it plays).
    public var profiles: [CompactLoudnessProfile]

    public init(
        mode: Mode, source: Source, continuousWithPrevious: Bool,
        unfolded: LevelNumbers, folded: FoldedNumbers?, roles: [UInt8],
        peakRate: Double? = nil, profiles: [CompactLoudnessProfile] = []
    ) {
        self.mode = mode
        self.source = source
        self.continuousWithPrevious = continuousWithPrevious
        self.unfolded = unfolded
        self.folded = folded
        self.roles = roles
        self.peakRate = peakRate
        self.profiles = profiles
    }

    /// No leveling and nothing known: the gain stays 0 dB while the fold's trim and the peak cap still apply,
    /// against an unknown (0 dBTP) peak. What every request carries until lane 3's decisions land (W5).
    public static let off = TrackLevelingDecision(
        mode: .off, source: .unknownCut, continuousWithPrevious: false,
        unfolded: LevelNumbers(loudness: nil, truePeak: nil), folded: nil, roles: []
    )
}

/// A saved compact −ΔL profile (§8½ C2): what the engine needs to know the loudness-neutral EQ gain the moment
/// its track becomes audible, so a fresh start of an analysed track never glides (NI-1). The analysis's own
/// form (`AsCompactProfileInfo`, TrackLoudnessBridge.h), carried as plain values so this Kit stays pure; the
/// playback bridge rebuilds the engine's profile from it before the track is audible.
public struct CompactLoudnessProfile: Sendable, Equatable {
    /// The programme the profile measured: as decoded (N channels), or the stereo fold at an LFE variant.
    public enum Basis: Sendable, Equatable {
        case decoded
        case fold(lfeVariant: Int)
    }

    public var basis: Basis
    /// The analysis's rate (the engine's), Hz.
    public var sampleRate: Double
    /// The band grid: 1/`bandsPerOctave`-octave bands from a 20 Hz first edge to Nyquist.
    public var bandsPerOctave: Int
    public var bandCount: Int
    public var blockCount: Int
    /// Kept block j starts at j × `blockStrideHops` × 100 ms (1 up to 1200 blocks; 2, 4, … past it).
    public var blockStrideHops: Int
    /// IEEE-754 binary16 bit patterns, block-major: `blockCount` × `bandCount` band powers.
    public var powers: [UInt16]

    public init(basis: Basis, sampleRate: Double, bandsPerOctave: Int, bandCount: Int, blockCount: Int,
                blockStrideHops: Int, powers: [UInt16]) {
        self.basis = basis
        self.sampleRate = sampleRate
        self.bandsPerOctave = bandsPerOctave
        self.bandCount = bandCount
        self.blockCount = blockCount
        self.blockStrideHops = blockStrideHops
        self.powers = powers
    }
}
