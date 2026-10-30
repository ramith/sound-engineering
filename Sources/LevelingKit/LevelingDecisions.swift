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
    ///
    /// - At a seam the judge calls continuous, the track inherits the decision `previous` plays with, so the level
    ///   never steps inside the music, whatever has landed since (an album finished analysing, a tag read).
    /// - Otherwise the scope decides. Album, and Auto beside a song of the same album, take the album's numbers
    ///   when every song is analysed, else its album tags when every song has the same ones, else the track's
    ///   own. Track and Off take the track's continuous run's numbers when the track joins its run in play order
    ///   and every song of the run is analysed, else the track's own: its analysis, then its track tags, then the
    ///   unknown cut.
    public func decision(for request: LevelingRequest) -> TrackLevelingDecision {
        guard let track = tracks[request.key] else {
            return Self.unknown(leveled: request.mode != .off)
        }
        let continuous = request.atSeam && continues(from: request.previous, into: request.key, track: track)
        if continuous, let previous = request.previousDecision {
            return Self.inherit(previous, by: track, mode: request.mode)
        }
        var decision = scoped(request, track: track)
        decision.continuousWithPrevious = continuous
        return decision
    }
}

/// One question to the decision builder: which track, in which mode, between which neighbours.
public struct LevelingRequest: Sendable, Equatable {
    /// The track's key (`LevelingLibrary.tracks`).
    public var key: String
    /// The listener's setting.
    public var mode: LevelingMode
    /// The track heard just before this one: at a seam, the one it follows; at a fresh start, the one played last
    /// in this session, if any. Auto reads it ("the one just played"); continuity reads it at a seam; a continuous
    /// run reads it and `next` (the track joins its run only beside its neighbour in the run).
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
    /// An edge block quieter than this is silence: BS.1770's absolute gate (−70 LUFS), below which the standard
    /// counts no programme. A seam is continuous unless one of its two edge blocks is silent.
    public static let silenceLufs = -70.0

    /// The one continuity judge (§4): whether a track whose last 400 ms block reads `tail` runs on into one whose
    /// first block reads `head` (LUFS; nil = unknown, which counts as sounding). Continuous unless an edge is
    /// silent. Measured on the live show (9i): applause, announcements and room tone run on across three of its
    /// four pauses, and its dips reach −53 LUFS inside the music, so the design's −50 LUFS stepped the level
    /// 6.9 dB at a dip; only a fade into digital silence and a 0.3 s fade to −72 LUFS read as silence there.
    public static func continuous(tail: Double?, head: Double?) -> Bool {
        let silent = { (edge: Double?) in edge.map { $0 < silenceLufs } ?? false }
        return !silent(tail) && !silent(head)
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

// MARK: - Scope

extension LevelingLibrary {
    /// Album tags of two songs that differ by more than this are not one album's level (dB).
    static let albumTagTolerance = 0.1

    /// The decision by `request`'s scope, before continuity.
    private func scoped(_ request: LevelingRequest, track: LevelingTrack) -> TrackLevelingDecision {
        let leveled = request.mode != .off
        let albumScope = switch request.mode {
        case .album: true
        case .auto: sharesAlbum(track, with: request.previous) || sharesAlbum(track, with: request.next)
        case .off, .track: false
        }
        if albumScope, let album = albumDecision(for: track, leveled: leveled) {
            return album
        }
        return trackDecision(for: track, request: request, leveled: leveled)
    }

    /// Whether the track `key` is from `track`'s album. A song with no album shares none.
    private func sharesAlbum(_ track: LevelingTrack, with key: String?) -> Bool {
        guard let album = track.album, let key, let other = tracks[key] else { return false }
        return other.album == album
    }

    /// The album's numbers: its analysis when every song has one, else its album tags when every song carries
    /// the same ones; nil when neither (the track's own decide).
    private func albumDecision(for track: LevelingTrack, leveled: Bool) -> TrackLevelingDecision? {
        guard let album = track.album, let keys = albums[album], !keys.isEmpty else { return nil }
        let members = keys.map { tracks[$0] }
        let measured = members.compactMap { $0?.measurement }
        if measured.count == keys.count {
            return Self.group(measured, own: track.measurement, leveled: leveled)
        }
        return Self.albumTags(members.map { $0?.tags?.albumLevel }, leveled: leveled)
    }

    /// The track's numbers: its continuous run's when it joins the run as it plays and every song of the run is
    /// analysed, else its own.
    private func trackDecision(for track: LevelingTrack, request: LevelingRequest,
                               leveled: Bool) -> TrackLevelingDecision {
        let run = continuousRun(of: request.key, album: track.album)
        if Self.joins(run, request) {
            let measured = run.compactMap { tracks[$0]?.measurement }
            if measured.count == run.count {
                return Self.group(measured, own: track.measurement, leveled: leveled)
            }
        }
        if let measurement = track.measurement {
            return Self.group([measurement], own: measurement, leveled: leveled)
        }
        if let level = track.tags?.trackLevel {
            return Self.tagged(level, leveled: leveled)
        }
        return Self.unknown(leveled: leveled)
    }
}

// MARK: - Continuity (the one judge, §4)

extension LevelingLibrary {
    /// Whether `key` runs on from `previous` across their seam: `previous` is the song before it on its album, and
    /// the judge hears no silence between them (an edge not measured counts as sounding).
    private func continues(from previous: String?, into key: String, track: LevelingTrack) -> Bool {
        guard let previous, let album = track.album, let members = albums[album],
              let index = members.firstIndex(of: key), index > 0, members[index - 1] == previous else { return false }
        return LevelingRules.continuous(tail: tracks[previous]?.measurement?.tailLoudness,
                                        head: track.measurement?.headLoudness)
    }

    /// The songs of `album` around `key` that join it without a pause, in album order (just `key` when none do,
    /// or when it is on no album).
    private func continuousRun(of key: String, album: Int64?) -> [String] {
        guard let album, let members = albums[album], let index = members.firstIndex(of: key) else { return [key] }
        let joined = { (left: Int) in
            LevelingRules.continuous(tail: tracks[members[left]]?.measurement?.tailLoudness,
                                     head: tracks[members[left + 1]]?.measurement?.headLoudness)
        }
        var first = index
        while first > 0, joined(first - 1) {
            first -= 1
        }
        var last = index
        while last < members.count - 1, joined(last) {
            last += 1
        }
        return Array(members[first ... last])
    }

    /// Whether `request`'s track joins `run` as it plays: the song before it in play order is the one before it in
    /// the run, or the song after it is the one after. A run shares one level because its songs join without a
    /// pause (founder, 2026-10-30); out of album order — shuffled, played alone, or the other way round — they never
    /// do, and each plays at its own level (founder, 2026-10-26, decision 2). Auto and Track alike; Off keeps the
    /// run's peaks by the same rule.
    private static func joins(_ run: [String], _ request: LevelingRequest) -> Bool {
        guard let index = run.firstIndex(of: request.key) else { return false }
        let before = index > run.startIndex ? run[index - 1] : nil
        let after = index + 1 < run.endIndex ? run[index + 1] : nil
        return (before != nil && request.previous == before) || (after != nil && request.next == after)
    }
}

// MARK: - The numbers

extension LevelingLibrary {
    /// A group's numbers (§3, §4): a whole album, a continuous run, or one track. L is its anchor, the loudest
    /// member of `anchorMinimumSeconds` or more (every member when none is that long); the peaks are its maxima;
    /// on each basis. One LFE variant: omitted unless every member that folds includes. Roles and profiles are
    /// `own`'s, the track that plays.
    private static func group(_ members: [LevelingTrack.Measurement], own: LevelingTrack.Measurement?,
                              leveled: Bool) -> TrackLevelingDecision {
        let long = members.filter { $0.durationSeconds >= LevelingRules.anchorMinimumSeconds }
        let pool = long.isEmpty ? members : long
        let loudness = pool.compactMap(\.loudness).max()
        let rates = Set(members.map(\.peakRate))
        var decision = TrackLevelingDecision(
            mode: !leveled ? .off : (loudness == nil ? .unknownCut : .leveled),
            source: loudness == nil ? .unknownCut : .analysis, continuousWithPrevious: false,
            unfolded: .init(loudness: loudness, truePeak: members.compactMap(\.truePeak).max()),
            folded: folded(members, pool: pool), roles: own?.roles ?? [], peakRate: rates.count == 1 ? rates.first : nil
        )
        decision.profiles = keptProfiles(own?.profiles ?? [], for: decision)
        return decision
    }

    /// The fold's numbers of a group: per variant, the anchor over `pool` and the peak over `members`. A member
    /// that does not fold counts as decoded (it plays as decoded beside the others). Nil when none folds.
    private static func folded(_ members: [LevelingTrack.Measurement],
                               pool: [LevelingTrack.Measurement]) -> TrackLevelingDecision.FoldedNumbers? {
        let folding = members.compactMap(\.folded)
        guard !folding.isEmpty else { return nil }
        let variant = folding.allSatisfy(\.lfeIncludes) ? LevelingRules.lfeIncludeVariant : .omit
        let indices = LfeVariant.allCases.map(\.rawValue)
        let loudness = indices.map { index in pool.compactMap { $0.foldedLoudness(variant: index) }.max() ?? .nan }
        let truePeak = indices.map { index in members.compactMap { $0.foldedTruePeak(variant: index) }.max() ?? .nan }
        return .init(loudness: loudness, truePeak: truePeak, variant: variant.rawValue)
    }

    /// The album's level by its album tags, when every song carries the same one (within `albumTagTolerance`); the
    /// highest of their album peaks.
    private static func albumTags(_ levels: [GainTags.Level?], leveled: Bool) -> TrackLevelingDecision? {
        let known = levels.compactMap(\.self)
        guard let first = known.first, known.count == levels.count,
              known.allSatisfy({ abs($0.loudness - first.loudness) <= albumTagTolerance }) else { return nil }
        return tagged(GainTags.Level(loudness: first.loudness, peak: known.compactMap(\.peak).max()),
                      leveled: leveled)
    }

    /// A decision from a tag's level: the loudness; its sample peak, at no known rate (the planner reads it as
    /// 0 dBTP unless it is above full scale, so a tag never raises a track); no fold numbers, no roles.
    private static func tagged(_ level: GainTags.Level, leveled: Bool) -> TrackLevelingDecision {
        TrackLevelingDecision(mode: leveled ? .leveled : .off, source: .tags, continuousWithPrevious: false,
                              unfolded: .init(loudness: level.loudness, truePeak: level.peak), folded: nil, roles: [])
    }

    /// Nothing known: the unknown cut (−5 dB, the planner's), or Off.
    private static func unknown(leveled: Bool) -> TrackLevelingDecision {
        TrackLevelingDecision(mode: leveled ? .unknownCut : .off, source: .unknownCut, continuousWithPrevious: false,
                              unfolded: .init(loudness: nil, truePeak: nil), folded: nil, roles: [])
    }

    /// At a continuous seam: `previous`'s numbers, variant, source and mode (Off when the listener's mode is Off);
    /// the track's own roles and profiles when it is analysed.
    private static func inherit(_ previous: TrackLevelingDecision, by track: LevelingTrack,
                                mode: LevelingMode) -> TrackLevelingDecision {
        var decision = previous
        decision.continuousWithPrevious = true
        if mode == .off {
            decision.mode = .off
        } else if previous.mode == .off {
            decision.mode = previous.source == .unknownCut ? .unknownCut : .leveled
        }
        if let own = track.measurement {
            decision.roles = own.roles
            decision.profiles = keptProfiles(own.profiles, for: decision)
        } else {
            decision.profiles = []
        }
        return decision
    }

    /// The profiles of `profiles` that `decision` plays on.
    private static func keptProfiles(_ profiles: [CompactLoudnessProfile],
                                     for decision: TrackLevelingDecision) -> [CompactLoudnessProfile] {
        let bases = decision.profileBases
        return profiles.filter { bases.contains($0.basis) }
    }
}

extension LevelingTrack.Measurement {
    /// L at fold variant `variant`; as decoded for a file that does not fold.
    func foldedLoudness(variant: Int) -> Double? {
        guard let folded else { return loudness }
        return folded.loudness.indices.contains(variant) ? folded.loudness[variant] : nil
    }

    /// TP at fold variant `variant`; as decoded for a file that does not fold.
    func foldedTruePeak(variant: Int) -> Double? {
        guard let folded else { return truePeak }
        return folded.truePeak.indices.contains(variant) ? folded.truePeak[variant] : nil
    }
}
