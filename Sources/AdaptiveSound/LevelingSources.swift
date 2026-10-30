import Foundation
import LevelingKit
import LibraryStore
import TrackLoudnessKit

// MARK: - What leveling reads, off the main thread (R1.1-B W5, lane 3-B; level-and-fold "The store and the scheduler")

/// What the leveling coordinator reads to decide: each file's identity, our analysis of it (the analysis store),
/// its loudness tags, and the library's albums. Every read is async and runs off the main thread; the app's are
/// `StoreLevelingSources`, a test's its own.
protocol LevelingSources: Sendable {
    /// The file's identity (path, size, mtime); nil when its attributes cannot be read.
    func identity(of url: URL) async -> TrackIdentity?
    /// The current-version analyses the store holds for `identities` (no profiles); an unanalysed one is absent.
    func analyses(for identities: [TrackIdentity]) async -> [TrackIdentity: TrackAnalysis]
    /// The saved profiles of `identity` on `bases` (the store's indices) that are still kept.
    func profiles(for identity: TrackIdentity, bases: [Int]) async -> [Int: TrackAnalysis.Profile]
    /// The file's ReplayGain / R128 tags; nil when it has none.
    func tags(of url: URL) async -> GainTags?
    /// The album of each library song in `trackIDs`; a song on no album (no album title) is absent.
    func albums(of trackIDs: [Int64]) async -> [Int64: Int64]
    /// An album's songs in album order (disc, then track): their files and lengths.
    func members(ofAlbum album: Int64) async -> [LevelingSlot]
}

/// One song as leveling sees it: its key (the standardized path, `TrackIdentity.path`), its file, its library id
/// (nil for a loose file) and its length (nil when not known).
struct LevelingSlot: Sendable, Equatable {
    let key: String
    let url: URL
    let trackID: Int64?
    let durationSeconds: Double?

    init(url: URL, trackID: Int64?, durationSeconds: Double?) {
        key = Self.key(of: url)
        self.url = url
        self.trackID = trackID
        self.durationSeconds = durationSeconds.flatMap { $0 > 0 ? $0 : nil }
    }

    /// The key LevelingKit and the analysis store know a file by: its standardized path.
    static func key(of url: URL) -> String {
        url.standardizedFileURL.path
    }
}

/// The app's sources: the analysis store (`track-analysis.sqlite3`, nil when it could not be opened), the library
/// store (nil until it opens), and the files themselves.
struct StoreLevelingSources: LevelingSources {
    let analysis: TrackAnalysisStore?
    let library: LibraryStore?

    func identity(of url: URL) async -> TrackIdentity? {
        TrackIdentity(url: url)
    }

    func analyses(for identities: [TrackIdentity]) async -> [TrackIdentity: TrackAnalysis] {
        guard let analysis, !identities.isEmpty else { return [:] }
        do {
            return try await analysis.analyses(for: identities)
        } catch {
            logUX("leveling: the analysis store could not be read (\(error)) — nothing counts as analysed")
            return [:]
        }
    }

    func profiles(for identity: TrackIdentity, bases: [Int]) async -> [Int: TrackAnalysis.Profile] {
        guard let analysis else { return [:] }
        return (try? await analysis.profiles(for: identity, bases: bases)) ?? [:]
    }

    func tags(of url: URL) async -> GainTags? {
        await GainTags(TrackGainTags.read(from: url))
    }

    func albums(of trackIDs: [Int64]) async -> [Int64: Int64] {
        guard let library, !trackIDs.isEmpty,
              let rows = try? await library.tracksDisplay(ids: trackIDs) else { return [:] }
        return rows.compactMapValues(\.albumID)
    }

    func members(ofAlbum album: Int64) async -> [LevelingSlot] {
        guard let library, let rows = try? await library.tracksDisplay(inAlbum: album) else { return [] }
        return rows.map { LevelingSlot(url: $0.url, trackID: $0.id, durationSeconds: Double($0.durationMs) / 1000) }
    }
}

// MARK: - What the coordinator knows of the horizon

/// What the coordinator knows of the queue's horizon, as one value: the decision builder's input (every song it may
/// be asked about, with its album-mates), each song's file, what was looked up, and the scheduler's jobs. Built
/// off the main thread (`LevelingLoad`), kept on it (`LevelingState`).
struct LevelingKnowledge: Sendable {
    var library = LevelingLibrary()
    var files: [String: URL] = [:]
    /// Each looked-up file's tags, by its identity (an edited file is read again); nil when it has none.
    var tags: [TrackIdentity: GainTags?] = [:]
    /// The songs whose record (or its absence) and tags were looked up.
    var resolved: Set<String> = []
    /// The analysed songs whose saved profiles were looked up too (C2: a start or arm carries them, so an analysed
    /// song's fresh start never glides).
    var profiled: Set<String> = []

    /// Whether a start of `key` has everything it needs: its record looked up, and its profiles if it has one.
    func isReadyToStart(_ key: String) -> Bool {
        resolved.contains(key) && (library.tracks[key]?.measurement == nil || profiled.contains(key))
    }

    /// The analysis jobs the horizon needs, most urgent first.
    var jobs: [TrackAnalysisScheduler.Job] = []

    /// `other`'s songs added to these (a start's own lookup joining the horizon's): its values win.
    mutating func merge(_ other: LevelingKnowledge) {
        library.tracks.merge(other.library.tracks) { _, new in new }
        library.albums.merge(other.library.albums) { _, new in new }
        files.merge(other.files) { _, new in new }
        tags.merge(other.tags) { _, new in new }
        resolved.formUnion(other.resolved)
        profiled.formUnion(other.profiled)
    }
}

/// The off-main lookups that turn the queue's upcoming songs into `LevelingKnowledge`, over `sources`, reusing
/// what `previous` read of files that did not change (their tags).
struct LevelingLoad: Sendable {
    let sources: any LevelingSources
    let previous: LevelingKnowledge

    /// The saved profiles to load for a song the engine is about to start or arm: as decoded, and — when it folds
    /// — the fold with the LFE omitted and at the include level, the two variants a decision can play (a group
    /// plays Omit unless every member includes, §4). The builder keeps exactly its decision's bases.
    static func profileBases(folds: Bool) -> [Int] {
        guard folds else { return [0] }
        let include = CompactLoudnessProfile.Basis.fold(lfeVariant: LevelingRules.lfeIncludeVariant.rawValue)
        let omit = CompactLoudnessProfile.Basis.fold(lfeVariant: LfeVariant.omit.rawValue)
        return Array(Set([0, omit.storeIndex, include.storeIndex])).sorted()
    }

    /// What the builder needs for `upcoming` — the play order from the current slot, the first entry the song
    /// playing (or about to) — within the horizon (`LevelingHorizon`): every song of each album it needs, every
    /// loose song it reaches, each with our analysis or else its tags, and the saved profiles of the songs in
    /// `profilesFor` (the ones the engine starts or arms next). Off the main thread; one store transaction for the
    /// analyses.
    @concurrent
    func horizon(_ upcoming: [LevelingSlot], profilesFor: Set<String>) async -> LevelingKnowledge {
        let albumOf = await sources.albums(of: upcoming.compactMap(\.trackID))
        let entries = upcoming.map { slot in
            LevelingHorizon.Entry(key: slot.key, album: slot.trackID.flatMap { albumOf[$0] },
                                  durationSeconds: slot.durationSeconds)
        }
        let needs = LevelingHorizon.needs(upcoming: entries)
        var knowledge = LevelingKnowledge()
        var slots: [LevelingSlot] = []
        var albumOfKey: [String: Int64] = [:]
        for id in Self.albumsToRead(needs: needs, entries: entries) {
            let members = await sources.members(ofAlbum: id)
            knowledge.library.albums[id] = members.map(\.key)
            for member in members {
                albumOfKey[member.key] = id
                slots.append(member)
            }
        }
        slots += Self.looseSlots(upcoming, needs: needs, albumOfKey: albumOfKey)
        await lookUp(slots, albumOfKey: albumOfKey, profilesFor: profilesFor, into: &knowledge)
        knowledge.jobs = Self.jobs(for: needs, knowledge: knowledge, upcoming: upcoming)
        return knowledge
    }

    /// One song's lookup, for a start that cannot wait for the horizon's (`AudioViewModel+Leveling`, the 50 ms
    /// wait): its record or tags, and its saved profiles.
    @concurrent
    func single(_ slot: LevelingSlot) async -> LevelingKnowledge {
        var album: Int64?
        if let trackID = slot.trackID {
            album = await sources.albums(of: [trackID])[trackID]
        }
        var knowledge = LevelingKnowledge()
        await lookUp([slot], albumOfKey: album.map { [slot.key: $0] } ?? [:], profilesFor: [slot.key],
                     into: &knowledge)
        return knowledge
    }

    /// The albums to read every member of: those the horizon analyses, and those of the two songs about to play
    /// whatever it says (Auto and an album's completeness read every member).
    private static func albumsToRead(needs: [LevelingHorizon.Need], entries: [LevelingHorizon.Entry]) -> [Int64] {
        let wanted = needs.compactMap { need -> Int64? in
            if case let .album(id) = need.target {
                return id
            }
            return nil
        } + entries.prefix(2).compactMap(\.album)
        var seen: Set<Int64> = []
        return wanted.filter { seen.insert($0).inserted }
    }

    /// The upcoming songs on no album that the horizon reaches, and the two about to play when on none.
    private static func looseSlots(_ upcoming: [LevelingSlot], needs: [LevelingHorizon.Need],
                                   albumOfKey: [String: Int64]) -> [LevelingSlot] {
        let looseKeys = Set(needs.compactMap { need -> String? in
            if case let .track(key) = need.target {
                return key
            }
            return nil
        })
        return upcoming.enumerated().compactMap { index, slot in
            (index < 2 || looseKeys.contains(slot.key)) && albumOfKey[slot.key] == nil ? slot : nil
        }
    }

    /// Identities, then the store's records in one read, then tags for the unanalysed and profiles for
    /// `profilesFor`, into `knowledge`.
    private func lookUp(_ slots: [LevelingSlot], albumOfKey: [String: Int64], profilesFor: Set<String>,
                        into knowledge: inout LevelingKnowledge) async {
        var identities: [String: TrackIdentity] = [:]
        for slot in slots where identities[slot.key] == nil {
            knowledge.files[slot.key] = slot.url
            if let identity = await sources.identity(of: slot.url) {
                identities[slot.key] = identity
            }
        }
        let analyses = await sources.analyses(for: Array(Set(identities.values)))
        for slot in slots where !knowledge.resolved.contains(slot.key) {
            let identity = identities[slot.key]
            let analysis = identity.flatMap { analyses[$0] }
            var tags: GainTags?
            if analysis == nil, let identity {
                tags = await readTags(of: slot.url, identity: identity)
                knowledge.tags[identity] = .some(tags)
            }
            var profiles: [Int: TrackAnalysis.Profile] = [:]
            if let analysis, let identity, profilesFor.contains(slot.key) {
                profiles = await sources.profiles(for: identity, bases: Self.profileBases(folds: analysis.folds))
                knowledge.profiled.insert(slot.key)
            }
            knowledge.library.tracks[slot.key] = LevelingTrack(
                album: albumOfKey[slot.key], measurement: analysis?.levelingMeasurement(profiles: profiles), tags: tags
            )
            knowledge.resolved.insert(slot.key)
        }
    }

    /// The file's tags: as read before if it did not change, else read now.
    private func readTags(of url: URL, identity: TrackIdentity) async -> GainTags? {
        if let kept = previous.tags[identity] {
            return kept
        }
        return await sources.tags(of: url)
    }

    /// The scheduler's jobs for the horizon's needs: an album's files in album order, a loose song's file.
    private static func jobs(for needs: [LevelingHorizon.Need], knowledge: LevelingKnowledge,
                             upcoming: [LevelingSlot]) -> [TrackAnalysisScheduler.Job] {
        needs.compactMap { need -> TrackAnalysisScheduler.Job? in
            switch need.target {
            case let .album(id):
                let files = (knowledge.library.albums[id] ?? []).compactMap { knowledge.files[$0] }
                return files.isEmpty ? nil
                    : TrackAnalysisScheduler.Job(id: "album \(id)", files: files, startsIn: need.startsIn)
            case let .track(key):
                guard let url = knowledge.files[key] ?? upcoming.first(where: { $0.key == key })?.url else {
                    return nil
                }
                return TrackAnalysisScheduler.Job(id: key, files: [url], startsIn: need.startsIn)
            }
        }
    }
}
