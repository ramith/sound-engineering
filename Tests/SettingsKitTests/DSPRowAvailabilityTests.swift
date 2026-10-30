// DSP-ROW — the shared "Off in bit-perfect mode" row state (R1.1-B, US-R1F-20 items 1–2): every control that
// changes the sound in the app's engine is registered, and while the path actually playing is Pure each one reads
// the state, with one action, Leave Pure. The state follows the path in use, never the Pure switch alone: Pure
// asked for while Enhanced plays (Bluetooth, a channel mismatch) leaves every row live.

@testable import SettingsKit
import Testing

@Suite("DSP rows — one state while Pure plays")
struct DSPRowAvailabilityTests {
    @Test("DSP-ROW-01: every registered row is inert while Pure plays, and live on Enhanced — whatever the switch says",
          arguments: DSPRow.allCases)
    func followsThePathInUse(row: DSPRow) {
        #expect(DSPRowAvailability(pathIsPure: true, pureRequested: true) == .notInBitPerfectMode(leaving: false))
        #expect(DSPRowAvailability(pathIsPure: false, pureRequested: true) == .live,
                "Pure asked for, Enhanced plays (Bluetooth, channels): the row works")
        #expect(DSPRowAvailability(pathIsPure: false, pureRequested: false) == .live)
        #expect(DSPRowAvailability(pathIsPure: true, pureRequested: false) == .notInBitPerfectMode(leaving: true),
                "Leave Pure pressed: Pure still plays until the next start, so the row stays inert and says so")
        #expect(!row.bitPerfectText.isEmpty)
    }

    @Test("DSP-ROW-02: the words — the shared state (also VoiceOver's hint), Leveling's own, the action")
    func words() {
        // Founder, 2026-10-30: "Off in bit-perfect mode" (it was "Not in bit-perfect mode", read as "Pure is off"); and
        // VoiceOver keeps the control's value and hears this state as the hint — the one constant.
        #expect(DSPRowAvailability.stateText == "Off in bit-perfect mode")
        #expect(DSPRow.leveling.bitPerfectText == "Leveling off (bit-perfect)")
        for row in DSPRow.allCases where row != .leveling {
            #expect(row.bitPerfectText == "Off in bit-perfect mode", "\(row)")
        }
        #expect(DSPRowAvailability.leaveAction == "Leave Pure")
        #expect(DSPRowAvailability.leavingText == "Enhanced starts the next time you start a song.")
        #expect(DSPRowAvailability.live.isLive)
        #expect(!DSPRowAvailability.notInBitPerfectMode(leaving: false).isLive)
    }

    @Test("DSP-ROW-03: the registry holds today's rows — EQ on / off, Tone, crossfeed, Leveling, Intensity")
    func registry() {
        #expect(Set(DSPRow.allCases) == [.equalizer, .tone, .crossfeed, .leveling, .intensity])
        #expect(Set(DSPRow.allCases.map(\.rawValue)).count == DSPRow.allCases.count)
    }
}
