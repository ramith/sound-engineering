// LEVEL-VM — the leveling coordinator on the real view model (R1.1-B W5, lane 3-B; level-and-fold §S3; US-R1F-10
// items 1, 4, 17–19): what each start and arm carries, the 50 ms wait at a start, the seam that makes the armed pick
// the song playing, the listener's mode change, the re-arm when the next song's analysis lands, and the prefetch of
// what the decision builder reads.
//
// The decisions are LevelingKit's (lane 3-A); these tests check that the coordinator asks the builder the right
// question — which song, in which mode, after which song and before which, at a seam or not, with what the song
// before plays — over what it has looked up, and passes the builder's answer on unchanged. So each expected decision
// is the builder's own answer to the expected question (`expected(…)`), never a decision written here.

@testable import AdaptiveSound
import Clocks
import Foundation
import LevelingKit
import PlaybackQueueKit
import RigKit
import SettingsKit
import Testing
import TrackLoudnessKit

@MainActor
@Suite("Leveling — the coordinator's requests (R1.1-B, §S3)", .timeLimit(.minutes(3)), .attachingLogTail)
struct LevelingCoordinatorTests {
    /// The key of FakePlayer's song `index`.
    private static func key(_ index: Int) -> String {
        LevelingSlot.key(of: track(index))
    }

    /// Sources where songs 0–2 make album 7 and song 3 is on no album; `analysed` songs carry a record (song 1's a
    /// 5.1 fold), the others none.
    private static func sources(analysed: Set<Int> = [0, 1, 2], hold: Hold? = nil) throws -> FakeLevelingSources {
        let sources = FakeLevelingSources(lookupHold: hold)
        var records: [String: TrackAnalysis] = [:]
        for index in analysed {
            records[key(index)] = try LevelingFixture.analysis(key(index), loudness: -10 - Double(index), truePeak: -1,
                                                               surround: index == 1,
                                                               lfe: index == 1 ? LevelingFixture.independentLfe
                                                                   : ["activeBlocks": 0])
        }
        let profile = try LevelingFixture.profile()
        sources.state.withLock { state in
            state.analyses = records
            for index in analysed {
                state.profiles[key(index)] = [0: profile, 1: profile, 2: profile]
            }
            state.albumOfTrack = [1: 7, 2: 7, 3: 7]
            state.members[7] = (0 ..< 3).map {
                LevelingSlot(url: track($0), trackID: Int64($0 + 1), durationSeconds: 200)
            }
        }
        return sources
    }

    /// A launched player over `sources`, Leveling at `mode`.
    private static func player(tracks: Int = 4, sources: FakeLevelingSources,
                               mode: LevelingSetting = .track) async throws -> FakePlayer {
        let player = try await FakePlayer.launched(tracks: tracks)
        player.vm.levelingState.testSources = sources
        player.vm.leveling = mode
        try await player.vm.settled()
        return player
    }

    /// The builder's answer, over what the coordinator knows now, to the question this test expects asked.
    private static func expected(_ player: FakePlayer, _ request: LevelingRequest) -> TrackLevelingDecision {
        player.vm.levelingState.knowledge.library.decision(for: request)
    }

    @Test("LEVEL-VM-01: a start carries the builder's answer for its song, between the song heard before and the next")
    func startCarriesTheBuildersDecision() async throws {
        let player = try await Self.player(sources: Self.sources())
        try await player.play(at: 0)
        try await player.vm.settled()
        let sent = try #require(player.engine.state.withLock(\.startLevelings).last)
        #expect(sent == Self.expected(player, LevelingRequest(key: Self.key(0), mode: .track, previous: nil,
                                                              next: Self.key(1), atSeam: false)))
        #expect(player.vm.levelingState.playing
            == .init(url: track(0), decision: sent, atSeam: false, previous: nil))
        #expect(player.vm.levelingState.knowledge.library.tracks[Self.key(0)]?.measurement != nil,
                "the song was looked up before it started")

        // The next start, another song: Auto's "just played" is the song before it.
        player.vm.playTrack(at: 2)
        try await player.vm.settled()
        try await until("the second start to land") { player.engine.state.withLock(\.startLevelings).count == 2 }
        let second = try #require(player.engine.state.withLock(\.startLevelings).last)
        #expect(second == Self.expected(player, LevelingRequest(key: Self.key(2), mode: .track,
                                                                previous: Self.key(0), next: Self.key(3))))
        #expect(player.vm.levelingState.playing?.previous == Self.key(0))
    }

    @Test("LEVEL-VM-02: a song not looked up yet waits for its lookup at most 50 ms, then starts with what is known")
    func startWaitsAtMostFiftyMilliseconds() async throws {
        try await withHold("the analysis store's read") { hold in
            let sources = try Self.sources(hold: hold)
            let player = try await Self.player(sources: sources)
            let clock = TestClock()
            player.vm.levelingState.clock = clock
            player.vm.playTrack(at: 0)
            try await hold.arrived()
            for _ in 0 ..< 50 {
                await Task.yield()
            }
            #expect(player.engine.state.withLock(\.startLevelings).isEmpty,
                    "the start waits — for the lookup, or the clock's 50 ms")
            // Only the clock moves; the store's read stays held.
            try await until("the start to go once 50 ms have passed") {
                await clock.advance(by: .milliseconds(50))
                return !player.engine.state.withLock(\.startLevelings).isEmpty
            }
            #expect(sources.state.withLock(\.analysisReads).isEmpty, "the lookup is still held: it started without it")
            let sent = try #require(player.engine.state.withLock(\.startLevelings).first)
            #expect(sent == LevelingLibrary().decision(for: LevelingRequest(key: Self.key(0), mode: .track,
                                                                            next: Self.key(1))),
                    "what is known of a song never looked up: nothing")

            hold.release()
            try await player.vm.settled()
            #expect(player.vm.levelingState.knowledge.library.tracks[Self.key(0)]?.measurement != nil,
                    "the lookup landed, for the next request")
            #expect(player.vm.levelingState.playing?.decision == sent, "and the song playing keeps its level")
        }
    }

    @Test("LEVEL-VM-03: a song the prefetch already looked up starts at once — the clock never moves")
    func lookedUpSongStartsAtOnce() async throws {
        let player = try await Self.player(sources: Self.sources())
        player.vm.selectedTrackIndex = 0
        try await player.vm.settled() // the prefetch for the selection
        #expect(player.vm.levelingState.knowledge.resolved.contains(Self.key(0)))
        player.vm.levelingState.clock = TestClock() // a wait would hang on it: the test's time never moves
        try await player.play(at: 0)
        #expect(player.engine.state.withLock(\.startLevelings).count == 1)
    }

    @Test("LEVEL-VM-04: every arm carries the builder's answer after the song playing; a seam makes it the one playing")
    func armAndSeam() async throws {
        let player = try await Self.player(sources: Self.sources())
        try await player.play(at: 0)
        try await player.vm.settled()
        let playing = try #require(player.vm.levelingState.playing)
        let armed = try #require(player.engine.state.withLock(\.nextLevelings).last ?? nil)
        #expect(armed == Self.expected(player, LevelingRequest(
            key: Self.key(1), mode: .track, previous: Self.key(0), next: Self.key(2), atSeam: true,
            previousDecision: playing.decision
        )))
        #expect(player.vm.levelingState.armed
            == .init(url: track(1), decision: armed, atSeam: true, previous: Self.key(0)))

        // The seam: song 1 plays, armed with that decision; song 2 is armed after it.
        player.engineReports(position: 0.2, transitionCount: 1)
        try player.tick()
        try await player.vm.settled()
        #expect(player.vm.selectedTrackIndex == 1)
        #expect(player.vm.levelingState.playing
            == .init(url: track(1), decision: armed, atSeam: true, previous: Self.key(0)))
        let next = try #require(player.engine.state.withLock(\.nextLevelings).last ?? nil)
        #expect(next == Self.expected(player, LevelingRequest(
            key: Self.key(2), mode: .track, previous: Self.key(1), next: Self.key(3), atSeam: true,
            previousDecision: armed
        )))
        #expect(player.vm.levelingState.armed?.previous == Self.key(1))
    }

    @Test("LEVEL-VM-05: the listener's mode change re-plans the song playing and the armed pick, each by its song")
    func modeChange() async throws {
        let player = try await Self.player(sources: Self.sources())
        try await player.play(at: 0)
        try await player.vm.settled()
        player.vm.leveling = .album
        try await player.vm.settled()
        let current = Self.expected(player, LevelingRequest(key: Self.key(0), mode: .album, next: Self.key(1)))
        let next = Self.expected(player, LevelingRequest(key: Self.key(1), mode: .album, previous: Self.key(0),
                                                         next: Self.key(2), atSeam: true, previousDecision: current))
        #expect(player.calls.last == .levelingChange(current: SongLeveling(url: track(0), decision: current),
                                                     next: SongLeveling(url: track(1), decision: next)))
        #expect(player.vm.levelingState.playing?.decision == current)
        #expect(player.vm.levelingState.armed?.decision == next)

        // The same mode again changes nothing.
        let before = player.calls.count
        player.vm.leveling = .album
        try await player.vm.settled()
        #expect(player.calls.count == before)
    }

    @Test("LEVEL-VM-06: a mode change with nothing playing, or with Pure playing, sends nothing")
    func modeChangeSendsNothingWithoutEnhancedPlayback() async throws {
        let idle = try await Self.player(sources: Self.sources())
        idle.vm.leveling = .album
        #expect(!idle.calls.contains {
            if case .levelingChange = $0 {
                return true
            } else {
                return false
            }
        })

        let pure = try await Self.player(sources: Self.sources())
        try await pure.play(at: 0)
        pure.engine.state.withLock { $0.signalPath.path = .pure }
        pure.engineReports(position: 1)
        try pure.tick()
        #expect(pure.vm.signalPath.path == .pure)
        pure.vm.leveling = .auto
        #expect(!pure.calls.contains {
            if case .levelingChange = $0 {
                return true
            } else {
                return false
            }
        },
        "Pure ignores leveling (deferred until the DAC)")
    }

    @Test("LEVEL-VM-07: the next song's analysis lands mid-song: re-armed with it while it is well ahead, never late",
          arguments: [(10.0, true), (196.0, false)])
    func rearmWhenTheArmedAnalysisLands(position: Double, wellAhead: Bool) async throws {
        let sources = try Self.sources(analysed: [0])
        let player = try await Self.player(sources: sources)
        try await player.play(at: 0)
        try await player.vm.settled()
        player.vm.duration = 200
        player.engineReports(position: position)
        try player.tick()
        let armed = try #require(player.vm.levelingState.armed)
        let picksBefore = player.engine.state.withLock(\.nextTracks).count

        let record = try LevelingFixture.analysis(Self.key(1), loudness: -9, truePeak: -0.5)
        sources.state.withLock { $0.analyses[Self.key(1)] = record }
        player.vm.scheduleLevelingRefresh() // the scheduler's report, as `onAnalysed` brings it
        try await player.vm.settled()

        let changed = Self.expected(player, LevelingRequest(
            key: Self.key(1), mode: .track, previous: Self.key(0), next: Self.key(2), atSeam: true,
            previousDecision: player.vm.levelingState.playing?.decision
        )) != armed.decision
        let picks = player.engine.state.withLock(\.nextTracks)
        if changed, wellAhead {
            #expect(picks.count == picksBefore + 1 && picks.last == track(1), "re-armed: the same pick, a new decision")
            #expect(player.engine.state.withLock(\.nextLevelings).last == player.vm.levelingState.armed?.decision)
        } else {
            #expect(picks.count == picksBefore, "no re-arm: \(changed ? "too close to the seam" : "nothing changed")")
        }
    }

    @Test("LEVEL-VM-08: the prefetch follows the queue — its songs, their albums' members, three songs' profiles")
    func prefetchFollowsTheQueue() async throws {
        let sources = try Self.sources(analysed: [0, 1, 2, 3])
        let player = try await Self.player(tracks: 5, sources: sources)
        try await player.play(at: 0)
        try await player.vm.settled()
        let knowledge = player.vm.levelingState.knowledge
        #expect(knowledge.library.albums[7] == (0 ..< 3).map(Self.key), "the album's members, in album order")
        for index in 0 ..< 3 {
            #expect(knowledge.library.tracks[Self.key(index)]?.album == 7)
        }
        #expect(knowledge.library.tracks[Self.key(1)]?.measurement?.folded?.lfeIncludes == true,
                "the LFE rule's verdict, computed at the boundary")
        let reads = sources.state.withLock(\.profileReads)
        #expect(reads.contains { $0.0 == Self.key(0) && $0.1 == [0] }, "a stereo song: as decoded")
        #expect(reads.contains { $0.0 == Self.key(1) && $0.1 == [0, 1, 2] },
                "a fold: as decoded, LFE omitted, LFE at the include level")
        #expect(reads.contains { $0.0 == Self.key(2) }, "the pick armed at the next seam: ready before it")
        #expect(player.vm.levelingState.knowledge.library.tracks[Self.key(3)]?.measurement != nil)
        #expect(!reads.contains { $0.0 == Self.key(3) }, "a fourth song: its record, not its profiles")

        // An edit of the queue refreshes what is known: a song appended joins as the next once the last plays.
        player.vm.appendToQueue([AudioFile(name: "t9", relativePath: "", absoluteURL: track(9), format: "FLAC",
                                           durationSeconds: 200, trackID: nil)])
        player.vm.selectedTrackIndex = 3
        try await player.vm.settled()
        #expect(player.vm.levelingState.knowledge.resolved.contains(Self.key(9)))
        #expect(player.vm.levelingState.knowledge.library.tracks[Self.key(9)]?.album == nil, "a loose file: no album")
    }

    @Test("LEVEL-VM-12: an album's job measures from the song about to play, then on, then the songs before it")
    func albumJobStartsAtTheSongPlaying() async throws {
        let player = try await Self.player(sources: Self.sources(analysed: []))
        try await player.play(at: 1)
        try await player.vm.settled()
        let job = try #require(player.vm.levelingState.knowledge.jobs.first { $0.id == "album 7" })
        #expect(job.files == [track(1), track(2), track(0)], "\(job.files.map(\.lastPathComponent))")
        #expect(job.startsIn == 0, "it plays now")
    }

    @Test("LEVEL-VM-09: a resume of the song playing carries the decision it plays with — no lookup, no new decision")
    func resumeKeepsTheDecision() async throws {
        let player = try await Self.player(sources: Self.sources())
        try await player.play(at: 0)
        try await player.vm.settled()
        let playing = try #require(player.vm.levelingState.playing)
        player.vm.startPlayback(resumeFrom: 30)
        try await player.vm.settled()
        try await until("the resume to land") { player.engine.state.withLock(\.startLevelings).count == 2 }
        #expect(player.engine.state.withLock(\.startLevelings).last == playing.decision)
        #expect(player.engine.state.withLock(\.startListens) == [.newPlay, .resume], "a resume says so")
        #expect(player.vm.levelingState.playing == playing)
    }
}

// MARK: - The listen a start plays (review B2, MEDIUM-1); a mode change that outran a request (review S2)

extension LevelingCoordinatorTests {
    @Test("LEVEL-VM-15: a mode change made while an on-deck request is on its way is sent again once it lands")
    func modeChangeThatOutranAnArmIsSentAgain() async throws {
        let player = try await Self.player(sources: Self.sources())
        try await player.play(at: 0)
        try await player.vm.settled()
        // Play Next arms song 2 — its request on its way, carrying a Track-mode decision — and the listener changes
        // the mode in the same turn: the engine may see the change before the arm, and drop its half for song 2.
        player.vm.playNext([audioFile(2)])
        player.vm.leveling = .off
        try await player.vm.settled()
        let arm = try #require(player.engine.state.withLock(\.nextLevelings).last ?? nil)
        let changes = player.engine.state.withLock(\.levelingChanges)
        let armed = try #require(player.vm.levelingState.armed)
        #expect(armed.url == track(2) && arm != armed.decision, "the precondition: the arm carried the old mode's")
        #expect(changes.count == 2, "sent \(changes.count) time(s): once at the change, once after the arm landed")
        #expect(changes.last?.next == SongLeveling(url: track(2), decision: armed.decision),
                "the re-send names the armed pick with its decision in the new mode")
        #expect(changes.last?.current == player.vm.levelingState.playing?.song)
    }

    @Test("LEVEL-VM-14: Pause → Play after the analysis landed keeps the song's level; Play after Stop decides afresh")
    func resumeAfterTheAnalysisLandedKeepsTheFirstDecision() async throws {
        let sources = try Self.sources(analysed: [])
        let player = try await Self.player(sources: sources)
        try await player.play(at: 0)
        try await player.vm.settled()
        let first = try #require(player.vm.levelingState.playing)
        #expect(first.decision.source == .unknownCut, "the precondition: an unmeasured first play")

        // The analysis lands mid-song, then the listener pauses and plays on.
        let record = try LevelingFixture.analysis(Self.key(0), loudness: -12, truePeak: -1)
        sources.state.withLock { $0.analyses[Self.key(0)] = record }
        player.vm.scheduleLevelingRefresh()
        try await player.vm.settled()
        player.vm.duration = 200
        player.engineReports(position: 30)
        try player.tick()
        player.vm.pause()
        try await player.vm.settled()
        player.vm.play()
        try await player.vm.settled()
        try await until("the resume to land") { player.engine.state.withLock(\.startLevelings).count == 2 }
        #expect(player.engine.state.withLock(\.startLevelings).last == first.decision,
                "the resume moved the level inside the song")
        #expect(player.engine.state.withLock(\.startListens).last == .resume)
        #expect(player.vm.levelingState.playing == first)

        // Stop, then Play: a new listen, decided afresh from the analysis.
        player.vm.stopPlayback()
        try await player.vm.settled()
        try await player.play(at: 0)
        try await player.vm.settled()
        let replay = try #require(player.engine.state.withLock(\.startLevelings).last)
        #expect(player.engine.state.withLock(\.startListens).last == .newPlay)
        #expect(replay.source == .analysis && replay.mode == .leveled, "\(replay.mode) from \(replay.source)")
    }
}

@MainActor
@Suite("Leveling — the setting and the boundary (R1.1-B)", .timeLimit(.minutes(3)), .attachingLogTail)
struct LevelingBoundaryTests {
    @Test("LEVEL-VM-10: Leveling comes back as left, and a change is kept (FD-2: Off on a new install)")
    func settingIsKept() {
        let world = IsolatedDefaults("LevelingSetting")
        let first = AudioViewModel(defaults: world.defaults, engine: FakeEngine())
        #expect(first.leveling == .off)
        first.leveling = .auto
        first.settingsStore.flush()
        let second = AudioViewModel(defaults: world.defaults, engine: FakeEngine())
        #expect(second.leveling == .auto)
    }

    @Test("LEVEL-VM-13: a start is ready with its record, album, profiles and next song; a merge keeps profiles")
    func readinessAndMerge() throws {
        let measured = try LevelingFixture.analysis("/m/a.flac", loudness: -12, truePeak: -1).levelingMeasurement()
        var knowledge = LevelingKnowledge()
        #expect(!knowledge.isReadyToStart("/m/a.flac", next: nil), "not looked up")
        knowledge.library.tracks["/m/a.flac"] = LevelingTrack(album: 7, measurement: measured)
        knowledge.resolved = ["/m/a.flac"]
        #expect(!knowledge.isReadyToStart("/m/a.flac", next: nil), "its album's members unknown")
        knowledge.library.albums[7] = ["/m/a.flac"]
        #expect(!knowledge.isReadyToStart("/m/a.flac", next: nil), "analysed, its profiles not looked up")
        knowledge.profiled = ["/m/a.flac"]
        #expect(knowledge.isReadyToStart("/m/a.flac", next: nil))
        #expect(!knowledge.isReadyToStart("/m/a.flac", next: "/m/b.flac"), "the next song not looked up")

        var withProfiles = measured
        withProfiles.profiles = try [LevelingFixture.profile().compact(basis: .decoded)]
        knowledge.library.tracks["/m/a.flac"]?.measurement = withProfiles
        var lookup = LevelingKnowledge()
        lookup.library.tracks["/m/a.flac"] = LevelingTrack(album: 7, measurement: measured) // a member, no profiles
        lookup.library.tracks["/m/b.flac"] = LevelingTrack(album: nil)
        lookup.resolved = ["/m/a.flac", "/m/b.flac"]
        knowledge.merge(lookup)
        #expect(knowledge.library.tracks["/m/a.flac"]?.measurement?.profiles.count == 1, "the profiles are kept")
        #expect(knowledge.isReadyToStart("/m/a.flac", next: "/m/b.flac"))
    }

    @Test("LEVEL-VM-11: the boundary — the record's numbers, the LFE rule's verdict, the profiles' bases, the tags")
    func boundary() throws {
        let stereo = try LevelingFixture.analysis("/m/a.flac", loudness: -12.5, truePeak: -0.7, head: -30, tail: nil)
        let measurement = try stereo.levelingMeasurement(profiles: [0: LevelingFixture.profile(7)])
        #expect(measurement.loudness == -12.5 && measurement.truePeak == -0.7 && measurement.peakRate == 48000)
        #expect(measurement.headLoudness == -30 && measurement.tailLoudness == nil && measurement.folded == nil)
        #expect(measurement.roles == [1, 2] && measurement.durationSeconds == 200)
        #expect(measurement.profiles.map(\.basis) == [.decoded] && measurement.profiles.first?.powers == [7, 7, 7, 7])

        let independent = try LevelingFixture.analysis("/m/b.flac", loudness: -14, truePeak: -1, surround: true,
                                                       lfe: LevelingFixture.independentLfe)
        let copied = try LevelingFixture.analysis("/m/c.flac", loudness: -14, truePeak: -1, surround: true,
                                                  lfe: LevelingFixture.copiedLfe)
        let silent = try LevelingFixture.analysis("/m/d.flac", loudness: -14, truePeak: -1, surround: true)
        #expect(independent.levelingMeasurement().folded?.lfeIncludes == true, "bass the mains do not carry")
        #expect(copied.levelingMeasurement().folded?.lfeIncludes == false, "a copy of the mains' bass")
        #expect(silent.levelingMeasurement().folded?.lfeIncludes == false, "under 5 s of LFE: unknown, omitted")
        #expect(independent.levelingMeasurement().folded?.loudness == [-14.0, -13.5, -12.8, -11.9])

        #expect(CompactLoudnessProfile.Basis(storeIndex: 0) == .decoded)
        #expect(CompactLoudnessProfile.Basis(storeIndex: 3) == .fold(lfeVariant: 2))
        #expect(CompactLoudnessProfile.Basis(storeIndex: 5) == nil)
        #expect(CompactLoudnessProfile.Basis.fold(lfeVariant: 1).storeIndex == 2)
        #expect(LevelingLoad.profileBases(folds: false) == [0])
        #expect(LevelingLoad.profileBases(folds: true) == [0, 1, 1 + LevelingRules.lfeIncludeVariant.rawValue])

        #expect(GainTags(TrackGainTags()) == nil)
        let tags = TrackGainTags(replayGainTrack: -6.2, replayGainTrackPeak: 0.98, r128Album: -1536)
        #expect(GainTags(tags) == GainTags(replayGainTrack: -6.2, replayGainTrackPeak: 0.98, r128Album: -1536))
        for setting in LevelingSetting.allCases {
            #expect(LevelingMode(setting).rawValue == setting.rawValue)
        }
    }
}
