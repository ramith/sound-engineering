// HEAR — what the listener hears from the EQ (EQ3; ui-plan §4): one rule for the graph's look, the
// strip's copy and Compare. The first fact that applies wins: Off, no engine, Pure Mode, a held Compare.

@testable import EQEditKit
import Testing

@Suite("EQAudibleState — what plays, and whether Compare can be held")
struct EQAudibleStateTests {
    @Test("HEAR-01: the precedence — Off, then no engine, then Pure Mode, then Compare")
    func precedence() {
        #expect(EQAudibleState(isOn: true, isComparing: false, pureModeEngaged: false, engineReady: true) == .playing)
        #expect(EQAudibleState(isOn: true, isComparing: true, pureModeEngaged: false, engineReady: true) == .comparing)
        #expect(EQAudibleState(isOn: false, isComparing: true, pureModeEngaged: false, engineReady: true) == .off)
        #expect(EQAudibleState(isOn: true, isComparing: true, pureModeEngaged: true, engineReady: true) == .pureMode)
        #expect(EQAudibleState(isOn: true, isComparing: false, pureModeEngaged: true, engineReady: false)
            == .engineNotReady)
        // Off wins over everything: an EQ that is off draws no response, engine or not, Pure Mode or not.
        #expect(EQAudibleState(isOn: false, isComparing: false, pureModeEngaged: false, engineReady: false) == .off)
        #expect(EQAudibleState(isOn: false, isComparing: false, pureModeEngaged: true, engineReady: true) == .off)
        #expect(!EQAudibleState(isOn: false, isComparing: false, pureModeEngaged: true, engineReady: false)
            .drawsResponse)
    }

    @Test("HEAR-04: an edit's readouts show wherever the EQ is on — playing, Pure Mode, no engine")
    func editReadouts() {
        for state in [EQAudibleState.playing, .pureMode, .engineNotReady] {
            #expect(state.showsEditReadouts, "\(state)")
        }
        #expect(!EQAudibleState.off.showsEditReadouts && !EQAudibleState.comparing.showsEditReadouts)
    }

    @Test("HEAR-02: the solid curve is the EQ's only while it plays (or will, once the engine runs)")
    func drawsResponse() {
        #expect(EQAudibleState.playing.drawsResponse)
        #expect(EQAudibleState.engineNotReady.drawsResponse)
        for state in [EQAudibleState.off, .comparing, .pureMode] {
            #expect(!state.drawsResponse, "\(state)")
        }
    }

    @Test("HEAR-03: Compare can be held only while the EQ really plays")
    func canCompare() {
        #expect(EQAudibleState.playing.canCompare)
        #expect(EQAudibleState.comparing.canCompare)
        for state in [EQAudibleState.off, .pureMode, .engineNotReady] {
            #expect(!state.canCompare, "\(state)")
        }
    }
}
