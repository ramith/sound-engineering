// CONT — the one continuity judge (level-and-fold §4; US-R1F-10 items 7 and 18; lane 1-B's finding 2): a seam is
// across silence only when an edge block is below BS.1770's absolute gate (−70 LUFS); otherwise the sound runs on
// across it — music, room tone or applause — and the level must not step there. Unknown counts as sounding.

import LevelingKit
import Testing

@Suite("The continuity judge: silence below −70 LUFS at either edge, else continuous")
struct ContinuityTests {
    @Test("CONT-01: the threshold is BS.1770's absolute gate; −200 (digital silence) is silence; unknown sounds")
    func threshold() {
        #expect(LevelingRules.silenceLufs == -70)
        #expect(LevelingRules.continuous(tail: -20, head: -20))
        #expect(LevelingRules.continuous(tail: -69.9, head: -69.9))
        #expect(!LevelingRules.continuous(tail: -70.1, head: -20))
        #expect(!LevelingRules.continuous(tail: -20, head: -200))
        #expect(LevelingRules.continuous(tail: nil, head: -20))
        #expect(LevelingRules.continuous(tail: nil, head: nil))
        #expect(!LevelingRules.continuous(tail: nil, head: -99))
    }

    /// The live show's eight seams (corpus 9i, measured by the analysis pass: piece N's tail, piece N+1's head):
    /// the README's "pause" or "dip", and the verdict the judge must give.
    @Test("CONT-02: the live show (9i): applause and room tone run on; only the two near-silent seams step",
          arguments: [
              // 5:29 pause: a fade into 0.8 s of digital silence
              (-61.4, -73.8, false),
              // 9:06 dip: the music fades to −72 LUFS for ~0.3 s, then the next song starts
              (-72.4, -27.8, false),
              (-41.9, -46.7, true), // 14:35 dip
              (-30.3, -32.1, true), // 16:44 pause: applause across the cut
              (-25.7, -26.1, true), // 17:51 pause: applause and an announcement
              (-37.8, -39.7, true), // 20:40 pause: room tone
              (-30.1, -44.4, true), // 21:43 dip
              (-39.1, -53.0, true), // 34:15 dip: the old −50 rule stepped 6.9 dB here, inside the music
          ])
    func liveShow(tail: Double, head: Double, continuous: Bool) {
        #expect(LevelingRules.continuous(tail: tail, head: head) == continuous)
    }
}
