// Break-it, R1.1-B sound half: the decision builder against the founder's decisions (LevelingKit, pure values).

import LevelingKit
import Testing

/// A live album (1) whose songs run into each other (room sound at every edge) — the corpus's 9i shape: a loud piece
/// among quieter ones — and a studio album (2) with silence between its songs.
private let live: [(String, LevelingTrack)] = [
    ("l1", Fixture.stereo(-20, peak: -6, head: -40, tail: -38)),
    ("l2", Fixture.stereo(-13.7, peak: -0.5, head: -38, tail: -36)), // the loud piece (9i's piece 8)
    ("l3", Fixture.stereo(-20.5, peak: -7, head: -36, tail: -45)), // 6.8 LU under it (9i's piece 9)
]
private let studio: [(String, LevelingTrack)] = [
    ("s1", Fixture.stereo(-11, peak: 0.5, head: -200, tail: -200)),
    ("s2", Fixture.stereo(-16, peak: -2, head: -200, tail: -200)),
]
private let library = Fixture.library([1: live, 2: studio])

@Suite("Break-it, sound: the decision builder against the founder's rules")
struct BreakItLevelingTests {
    @Test("BI-S10: Auto in shuffle — a live album's song between two other albums' songs plays at its OWN level")
    func autoShuffleIsTheTracksOwnLevel() {
        // The founder (2026-10-26, decision 2): "Auto in shuffle keeps the decided rule: album level only when the
        // neighbouring song is from the same album; shuffled songs each at their own track level." Shuffle plays l3
        // between s1 and s2: no neighbour is from its album, no seam runs on into it, so its own level (−20.5 LUFS).
        let decision = library.decision(for: LevelingRequest(key: "l3", mode: .auto, previous: "s1", next: "s2",
                                                             atSeam: true))
        #expect(!decision.continuousWithPrevious)
        let loudness = decision.unfolded.loudness.map { "\($0)" } ?? "unknown"
        #expect(decision.unfolded.loudness == -20.5,
                "shuffled l3 plays at its continuous run's loudest member's level (\(loudness) LUFS), not its own")
    }
}
