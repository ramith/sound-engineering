// DEC — the decision builder (level-and-fold §3, §4, §S3; US-R1F-10 items 1–8 and 18; the founder's decisions of
// 2026-10-26 and 2026-10-30): the scope (track, continuous run, album), the source (analysis → tags → unknown), the
// continuity verdict and its inheritance, the album anchor, the group's LFE variant. The plan check's §6 "Auto rule"
// counter-examples are DEC-01…08.

import LevelingKit
import Testing

/// A studio album (1) with silence between its songs, a second album (2), a live album (3) whose seams run on
/// except one, and two loose files.
private let studio: [(String, LevelingTrack)] = [
    ("x1", Fixture.stereo(-20, peak: -3, head: -200, tail: -200)),
    ("x2", Fixture.stereo(-14, peak: -1, head: -200, tail: -200)),
    ("x3", Fixture.stereo(-24, peak: -6, head: -200, tail: -200)),
]
private let other: [(String, LevelingTrack)] = [
    ("y1", Fixture.stereo(-11, peak: 0.5, head: -200, tail: -200)),
    ("y2", Fixture.stereo(-16, peak: -2, head: -200, tail: -200)),
]
private let live: [(String, LevelingTrack)] = [
    ("p1", Fixture.stereo(-20, peak: -5, head: -45, tail: -30)),
    ("p2", Fixture.stereo(-13, peak: 0.1, head: -30, tail: -90)), // p2 → p3: a fade into silence
    ("p3", Fixture.stereo(-18, peak: -4, head: -80, tail: -40)),
    ("p4", Fixture.stereo(-25, peak: -5, head: -45, tail: -200)),
]
private let loose: [String: LevelingTrack] = [
    "a": Fixture.stereo(-9, peak: 1, head: -20, tail: -20),
    "b": Fixture.stereo(-19, peak: -2, head: -20, tail: -20),
]
private let library = Fixture.library([1: studio, 2: other, 3: live], loose: loose)

private func decide(_ key: String, _ mode: LevelingMode, previous: String? = nil, next: String? = nil,
                    atSeam: Bool = false, previousDecision: TrackLevelingDecision? = nil,
                    in lib: LevelingLibrary = library) -> TrackLevelingDecision {
    lib.decision(for: LevelingRequest(key: key, mode: mode, previous: previous, next: next, atSeam: atSeam,
                                      previousDecision: previousDecision))
}

@Suite("The decision builder: Auto, Album and Track (plan check §6, the Auto rule)")
struct LevelingScopeTests {
    @Test("DEC-01: shuffle A(X) → B(Y) → C(X): all three at their own level")
    func shuffleAcrossAlbums() {
        #expect(decide("x1", .auto, next: "y1").loudness == -20)
        #expect(decide("y1", .auto, previous: "x1", next: "x2", atSeam: true).loudness == -11)
        #expect(decide("x2", .auto, previous: "y1", atSeam: true).loudness == -14)
        #expect(decide("x1", .auto, next: "y1").source == .analysis)
    }

    @Test("DEC-02: shuffle plays X1 then X2: both at the album's level — its loudest song's, its highest peak")
    func shuffleWithinAnAlbum() {
        let first = decide("x1", .auto, next: "x2")
        let second = decide("x2", .auto, previous: "x1", atSeam: true)
        #expect(first.loudness == -14 && first.unfolded.truePeak == -1)
        #expect(second.unfolded == first.unfolded)
        #expect(first.mode == .leveled && first.source == .analysis)
        #expect(decide("x3", .auto, previous: "x1").loudness == -14) // just played, not adjacent: the same album
    }

    @Test("DEC-03: a song with no album is never 'the same album' — loose files next to each other each own")
    func noAlbumIsNeverTheSameAlbum() {
        #expect(decide("a", .auto, previous: "b", next: "b").loudness == -9)
        #expect(decide("b", .album, previous: "a").loudness == -19) // Album mode on a loose file: its own
    }

    @Test("DEC-04: a compilation is one album: Album mode gives every member the same numbers")
    func compilation() {
        let numbers = ["x1", "x2", "x3"].map { decide($0, .album).unfolded }
        #expect(Set(numbers.map(\.loudness)) == [-14] && Set(numbers.map(\.truePeak)) == [-1])
    }

    @Test("DEC-05: Track mode, album order: a continuous run shares its loudest member's level (founder, 2026-10-30)")
    func trackModeRuns() {
        // The live album in its own order: p1 → p2 runs on, p2 → p3 is silent, p3 → p4 runs on.
        #expect(decide("p1", .track, next: "p2").loudness == -13) // run p1–p2: p2 is the loudest
        #expect(decide("p1", .track, next: "p2").unfolded.truePeak == 0.1) // and the run's highest peak
        #expect(decide("p2", .track, previous: "p1", next: "p3").loudness == -13)
        #expect(decide("p3", .track, previous: "p2", next: "p4").loudness == -18) // run p3–p4
        #expect(decide("p4", .track, previous: "p3").loudness == -18)
        #expect(decide("p4", .album).loudness == -13) // the album's anchor is p2
    }

    @Test("DEC-17: a run's song that does not join it in play order plays at its own level — Track and Off alike")
    func runOutOfOrder() {
        // The run exists for songs "that join without a pause" (founder, 2026-10-30); shuffled songs never join, so
        // each plays at its own level (decision 2, 2026-10-26). p1 between songs of other albums:
        #expect(decide("p1", .track, previous: "y1", next: "x1").loudness == -20)
        #expect(decide("p1", .track).loudness == -20) // played alone
        // Beside its run-mate, but the other way round: p2 → p1, or p4 → p3. Nothing joins without a pause there.
        #expect(decide("p1", .track, previous: "p2").loudness == -20)
        #expect(decide("p4", .track, next: "p3").loudness == -25)
        #expect(decide("p4", .track, previous: "p2", next: "p1").loudness == -25) // its album, not its neighbours
        // Off keeps the numbers by the same rule: a lone song's own fold peak, not the run's worst.
        let lib = Fixture.library([5: [
            ("s1", Fixture.surround(-20, peak: -2, foldLoudness: -19, foldPeak: 1, includes: false)),
            ("s2", Fixture.surround(-18, peak: -3, foldLoudness: -17, foldPeak: 3, includes: false)),
        ]], loose: loose)
        #expect(decide("s1", .off, previous: "a", next: "b", in: lib).folded?.truePeak.first == 1)
    }

    @Test("DEC-06: Track mode with silence between songs: each song at its own level")
    func trackModeSilence() {
        #expect(["x1", "x2", "x3"].map { decide($0, .track).loudness } == [-20, -14, -24])
    }

    @Test("DEC-07: Album mode before the album is analysed: its tags if every song has them, else each its own")
    func albumModeBeforeAnalysis() {
        let tagged = { (track: Double, album: Double) in
            LevelingTrack(album: nil, tags: GainTags(replayGainTrack: track, replayGainAlbum: album))
        }
        var complete = Fixture.library([7: [("t1", tagged(-2, -4)), ("t2", tagged(-6, -4))]])
        let byTags = decide("t1", .album, in: complete)
        #expect(byTags.source == .tags && byTags.mode == .leveled && byTags.loudness == -14)
        #expect(byTags.peakRate == nil && byTags.folded == nil)
        complete.tracks["t2"]?.tags?.replayGainAlbum = nil // a member without the album tag
        let own = decide("t1", .album, in: complete)
        #expect(own.source == .tags && own.loudness == -16) // t1's own track tag
        complete.tracks["t2"] = Fixture.stereo(-15, album: 7) // t2 analysed, t1 not: still incomplete
        #expect(decide("t2", .album, in: complete).loudness == -15)
        #expect(decide("t2", .album, in: complete).source == .analysis)
    }

    @Test("DEC-07b: album tags that disagree between the songs are no album level")
    func albumTagsDisagree() {
        let lib = Fixture.library([7: [
            ("t1", LevelingTrack(album: nil, tags: GainTags(replayGainTrack: -2, replayGainAlbum: -4))),
            ("t2", LevelingTrack(album: nil, tags: GainTags(replayGainTrack: -6, replayGainAlbum: -1))),
        ]])
        #expect(decide("t2", .album, in: lib).loudness == -12) // its own track tag
    }

    @Test("DEC-08: a loose file gets its own level, or the unknown cut")
    func looseFile() {
        #expect(decide("a", .album).source == .analysis)
        let lib = LevelingLibrary(tracks: ["c": LevelingTrack(album: nil)])
        let unknown = decide("c", .auto, in: lib)
        #expect(unknown.mode == .unknownCut && unknown.source == .unknownCut && unknown.loudness == nil)
    }
}

@Suite("The decision builder: sources, Off, the anchor and the fold's group numbers")
struct LevelingNumbersTests {
    @Test("DEC-09: analysis first, then the track's tags, then the unknown cut; a track nobody knows is unknown")
    func sources() {
        var lib = LevelingLibrary(tracks: [
            "m": Fixture.stereo(-12, peak: -0.5),
            "t": LevelingTrack(album: nil, tags: GainTags(replayGainTrack: -3, replayGainTrackPeak: 1)),
            "u": LevelingTrack(album: nil),
        ])
        lib.tracks["m"]?.tags = GainTags(replayGainTrack: 9) // ignored: the track is analysed
        let measured = decide("m", .track, in: lib)
        #expect(measured.source == .analysis && measured.loudness == -12 && measured.peakRate == 48000)
        #expect(measured.roles == Fixture.stereoRoles && measured.unfolded.truePeak == -0.5)
        let tagged = decide("t", .track, in: lib)
        #expect(tagged.source == .tags && tagged.loudness == -15 && tagged.unfolded.truePeak == 0)
        #expect(tagged.roles.isEmpty && tagged.profiles.isEmpty)
        #expect(decide("u", .track, in: lib).mode == .unknownCut)
        let nobody = decide("zz", .track, in: lib)
        #expect(nobody.mode == .unknownCut && nobody.source == .unknownCut)
        #expect(decide("zz", .off, in: lib).mode == .off)
    }

    @Test("DEC-09b: an analysed silent track is unknown loudness, its known peak kept (NI-7)")
    func silentTrack() {
        let lib = LevelingLibrary(tracks: ["s": Fixture.stereo(nil, peak: -200)])
        let silent = decide("s", .track, in: lib)
        #expect(silent.mode == .unknownCut && silent.source == .unknownCut && silent.unfolded.truePeak == -200)
    }

    @Test("DEC-10: Off keeps the numbers — the fold's trim stays exact, and a continuous run shares one trim")
    func offKeepsNumbers() {
        let lib = Fixture.library([5: [
            ("s1", Fixture.surround(-20, peak: -2, foldLoudness: -19, foldPeak: 1, includes: false)),
            ("s2", Fixture.surround(-18, peak: -3, foldLoudness: -17, foldPeak: 3, includes: false)),
        ]])
        let off = decide("s1", .off, next: "s2", in: lib) // in album order
        #expect(off.mode == .off && off.source == .analysis)
        #expect(off.folded?.truePeak.first == 3) // the run's worst fold peak: one trim for s1 and s2
        #expect(off.folded?.variant == 0)
    }

    @Test("DEC-11: the album anchors on its loudest song of 30 s or more; the peak is every song's")
    func anchorGuard() {
        let lib = Fixture.library([6: [
            ("intro", Fixture.stereo(-8, peak: 2, seconds: 20, head: -200, tail: -200)),
            ("song", Fixture.stereo(-15, peak: -1, head: -200, tail: -200)),
            ("ballad", Fixture.stereo(-20, peak: -4, head: -200, tail: -200)),
        ]])
        let album = decide("ballad", .album, in: lib)
        #expect(album.loudness == -15 && album.unfolded.truePeak == 2)
        let short = Fixture.library([6: [
            ("i1", Fixture.stereo(-8, seconds: 20)), ("i2", Fixture.stereo(-12, seconds: 25)),
        ]])
        #expect(decide("i2", .album, in: short).loudness == -8) // all short: every song counts
    }

    @Test("DEC-12: a group plays one LFE variant — omitted unless every song includes — at its maxima")
    func groupLfe() throws {
        let mixed = Fixture.library([5: [
            ("s1", Fixture.surround(-20, peak: -2, foldLoudness: -19, foldPeak: -3, includes: true, bump: 1)),
            ("s2", Fixture.surround(-18, peak: -6, foldLoudness: -21, foldPeak: -1, includes: false, bump: 1,
                                    head: -200)),
        ]])
        let omitted = try #require(decide("s1", .album, in: mixed).folded)
        #expect(omitted.variant == 0)
        #expect(omitted.loudness == [-19, -18, -17, -16]) // per variant, the loudest song's
        #expect(omitted.truePeak == [-1, 0, 1, 2]) // per variant, the highest peak
        var both = mixed
        both.tracks["s2"]?.measurement?.folded?.lfeIncludes = true
        let included = decide("s2", .album, in: both)
        #expect(included.folded?.variant == LevelingRules.lfeIncludeVariant.rawValue)
        #expect(included.profiles.map(\.basis) == [.decoded, .fold(lfeVariant: 1)])
        #expect(decide("s1", .track, in: mixed).folded?.variant == 1) // alone (s1 → s2 is silent), s1 includes
        #expect(decide("s2", .track, in: mixed).profiles.map(\.basis) == [.decoded, .fold(lfeVariant: 0)])
    }

    @Test("DEC-18: a mono song is heard as dual mono: the anchor compares it so, the decision is in its own measure")
    func monoInAGroup() {
        // A mono song plays on both sides at 0 dB (F8): −22 LUFS on its one channel is heard at −18.99, louder than
        // the stereo song's −20, so it anchors the album. Every member's decision states that level in its own
        // measure, and the planner adds dual mono back for the mono one alone — one g for the album.
        let lib = Fixture.library([9: [
            ("st", Fixture.stereo(-20, peak: -10, head: -200, tail: -200)),
            ("mo", Fixture.mono(-22, peak: -10, head: -200, tail: -200)),
        ]])
        let heard = -22 + LevelingRules.dualMonoLu
        let stereo = decide("st", .album, in: lib)
        let mono = decide("mo", .album, in: lib)
        #expect(stereo.loudness.map { abs($0 - heard) < 1e-9 } == true, "anchor \(stereo.loudness ?? .nan)")
        #expect(mono.loudness.map { abs($0 - (heard - LevelingRules.dualMonoLu)) < 1e-9 } == true,
                "mono member's L \(mono.loudness ?? .nan)")
        #expect(mono.roles == Fixture.monoRoles && stereo.roles == Fixture.stereoRoles)
        #expect(decide("mo", .track, in: lib).loudness == -22) // alone: its own measure, as the planner expects
        #expect(decide("st", .track, in: lib).loudness == -20)
    }

    @Test("DEC-18b: a continuous seam between a stereo and a mono song carries the level on as heard")
    func monoInheritsAsHeard() throws {
        // One live album whose three songs run on: stereo −20, mono −25 (heard −21.99), stereo −30. Played in
        // order, the first takes the run's level (−20, its own: the loudest as heard); the others inherit it.
        let lib = Fixture.library([9: [
            ("st", Fixture.stereo(-20, peak: -10)), ("mo", Fixture.mono(-25, peak: -10)), ("st2", Fixture.stereo(-30)),
        ]])
        let first = decide("st", .track, next: "mo", in: lib)
        #expect(first.loudness == -20)
        let mono = decide("mo", .track, previous: "st", next: "st2", atSeam: true, previousDecision: first, in: lib)
        #expect(mono.continuousWithPrevious && mono.roles == Fixture.monoRoles)
        let monoL = try #require(mono.loudness)
        #expect(abs(monoL - (-20 - LevelingRules.dualMonoLu)) < 1e-9, "mono after stereo: L \(monoL)")
        let last = decide("st2", .track, previous: "mo", atSeam: true, previousDecision: mono, in: lib)
        #expect(last.continuousWithPrevious)
        #expect(last.loudness.map { abs($0 - -20) < 1e-9 } == true, "stereo after mono: L \(last.loudness ?? .nan)")
    }

    @Test("DEC-12b: a stereo song keeps its decoded profile; a group's decision keeps the song's own roles")
    func profilesAndRoles() {
        let stereo = decide("x2", .album)
        #expect(stereo.profiles.map(\.basis) == [.decoded] && stereo.roles == Fixture.stereoRoles)
    }
}

@Suite("The decision builder: continuity, and the level that never steps at a continuous seam")
struct LevelingContinuityTests {
    @Test("DEC-13: continuous only at a seam after the album's previous song, by the judge")
    func continuityFlag() {
        #expect(decide("p2", .track, previous: "p1", atSeam: true).continuousWithPrevious)
        #expect(!decide("p2", .track, previous: "p1", atSeam: false).continuousWithPrevious) // a fresh start
        #expect(!decide("p3", .track, previous: "p2", atSeam: true).continuousWithPrevious) // across silence
        #expect(!decide("p3", .track, previous: "p1", atSeam: true).continuousWithPrevious) // not adjacent
        #expect(!decide("x2", .track, previous: "x1", atSeam: true).continuousWithPrevious) // studio gaps
        #expect(!decide("b", .track, previous: "a", atSeam: true).continuousWithPrevious) // loose: no album
    }

    @Test("DEC-14: a continuous seam inherits the previous song's numbers — the album finished mid-song")
    func inheritance() {
        // p1 started before the album was analysed: it plays its own unknown cut. The analysis lands; at the
        // continuous seam p1 → p2 the level must not step, so p2 takes p1's decision, with its own roles.
        let playing = TrackLevelingDecision(mode: .unknownCut, source: .unknownCut, continuousWithPrevious: false,
                                            unfolded: .init(loudness: nil, truePeak: nil), folded: nil, roles: [])
        let next = decide("p2", .album, previous: "p1", atSeam: true, previousDecision: playing)
        #expect(next.mode == .unknownCut && next.source == .unknownCut && next.loudness == nil)
        #expect(next.continuousWithPrevious && next.roles == Fixture.stereoRoles)
        #expect(next.profiles.map(\.basis) == [.decoded])
        // At the next seam across silence (p2 → p3) the album's level starts.
        let after = decide("p3", .album, previous: "p2", atSeam: true, previousDecision: next)
        #expect(after.loudness == -13 && !after.continuousWithPrevious)
    }

    @Test("DEC-15: Album mode on a continuous album before analysis: the first song's level carries through")
    func unanalysedContinuousAlbum() {
        let parts = (1 ... 3).map { index in
            ("c\(index)", LevelingTrack(album: nil, tags: GainTags(replayGainTrack: Double(-index))))
        }
        var lib = Fixture.library([8: parts])
        lib.tracks["c3"]?.tags = nil // partial tags (9b): no album level; unanalysed seams count as sounding
        let first = decide("c1", .album, next: "c2", in: lib)
        #expect(first.loudness == -17 && first.source == .tags)
        let second = decide("c2", .album, previous: "c1", next: "c3", atSeam: true, previousDecision: first, in: lib)
        #expect(second.loudness == -17 && second.continuousWithPrevious)
        let third = decide("c3", .album, previous: "c2", atSeam: true, previousDecision: second, in: lib)
        #expect(third.loudness == -17 && third.source == .tags)
    }

    @Test("DEC-16: a mode change to Off while inheriting gives Off, the numbers kept")
    func inheritanceOff() {
        let playing = decide("p1", .track)
        let next = decide("p2", .off, previous: "p1", atSeam: true, previousDecision: playing)
        #expect(next.mode == .off && next.unfolded == playing.unfolded)
    }
}
