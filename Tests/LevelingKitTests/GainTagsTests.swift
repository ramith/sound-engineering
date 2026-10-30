// TAGS — the gain tags' conversion to the −18 LUFS target (US-R1F-10 item 4): ReplayGain 2.0 is relative to
// −18 LUFS, EBU R128's Q7.8 gains to −23 LUFS; a tag that implies a loudness no programme has is ignored.

import Foundation
import LevelingKit
import Testing

@Suite("GainTags — ReplayGain 2.0 and R128 to the −18 LUFS target")
struct GainTagsTests {
    @Test("TAGS-01: a ReplayGain 2.0 track gain of −7.53 dB says −10.47 LUFS; its peak 0.988 says −0.105 dBFS")
    func replayGain() throws {
        let level = try #require(GainTags(replayGainTrack: -7.53, replayGainTrackPeak: 0.988).trackLevel)
        #expect(abs(level.loudness - -10.47) < 1e-9)
        #expect(abs((level.peak ?? .nan) - 20 * log10(0.988)) < 1e-9)
    }

    @Test("TAGS-02: an R128 gain of −1280 (Q7.8: −5 dB, relative to −23 LUFS) says −18 LUFS; no peak")
    func r128() throws {
        let level = try #require(GainTags(r128Track: -1280).trackLevel)
        #expect(abs(level.loudness - -18) < 1e-9)
        #expect(level.peak == nil)
        let album = try #require(GainTags(r128Album: 512).albumLevel)
        #expect(abs(album.loudness - -25) < 1e-9)
    }

    @Test("TAGS-03: ReplayGain 2.0 wins when both are written; none written says nothing")
    func precedence() {
        let both = GainTags(replayGainTrack: -2, r128Track: 0)
        #expect(both.trackLevel?.loudness == -16)
        #expect(GainTags().trackLevel == nil && GainTags().albumLevel == nil)
        #expect(GainTags(replayGainTrack: -2).albumLevel == nil)
    }

    @Test("TAGS-04: the album's level from its album tags, with the album peak")
    func album() throws {
        let level = try #require(GainTags(replayGainAlbum: 3.4, replayGainAlbumPeak: 0.5).albumLevel)
        #expect(abs(level.loudness - -21.4) < 1e-9)
        #expect(abs((level.peak ?? .nan) - 20 * log10(0.5)) < 1e-9)
    }

    @Test("TAGS-05: a tag implying a loudness above 0 LUFS (9d's track gain −20 dB: +2 LUFS) or under −70 is ignored")
    func implausible() {
        #expect(GainTags(replayGainTrack: -20).trackLevel == nil) // +2 LUFS: louder than any programme
        #expect(GainTags(replayGainTrack: -18).trackLevel?.loudness == 0) // the edge stands
        #expect(GainTags(replayGainAlbum: 12).albumLevel?.loudness == -30) // 9d's album +12 dB: quiet, but possible
        #expect(GainTags(replayGainAlbum: 53).albumLevel == nil) // −71 LUFS: below BS.1770's absolute gate
        #expect(GainTags(replayGainTrack: .nan).trackLevel == nil)
        #expect(GainTags(replayGainTrack: -2, replayGainTrackPeak: 0).trackLevel?.peak == nil) // no peak in a 0
    }
}
