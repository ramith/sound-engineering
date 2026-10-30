// SEAM — LevelingKit's values that other code reads by number or by name (R1.1-B W5, lane 3-A's seam): the
// setting's stored names, the LFE variants' indices into TrackPlanBridge.h's table, and the profile bases a
// decision plays on.

import LevelingKit
import Testing

@Suite("LevelingKit's seam: stored names, the variant table's indices, the profile bases")
struct LevelingKitSeamTests {
    @Test("SEAM-01: the setting's stored names, and Off first")
    func modeNames() {
        #expect(LevelingMode.allCases.map(\.rawValue) == ["off", "auto", "album", "track"])
    }

    @Test("SEAM-02: the LFE variants are AsLfeVariant's indices; the include level is −6 dB per side")
    func variantIndices() {
        #expect(LfeVariant.allCases.map(\.rawValue) == [0, 1, 2, 3])
        #expect(LevelingRules.lfeIncludeVariant == .music)
    }

    @Test("SEAM-03: a decision plays on the decoded basis, and on its fold's variant when it folds")
    func profileBases() {
        #expect(TrackLevelingDecision.off.profileBases == [.decoded])
        var folded = TrackLevelingDecision.off
        folded.folded = .init(loudness: [-20, -19, -18, -17], truePeak: [-3, -2, -1, 0], variant: 1)
        #expect(folded.profileBases == [.decoded, .fold(lfeVariant: 1)])
    }
}
