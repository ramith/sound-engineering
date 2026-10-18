// R1.1-A close-out break-it (P3a, audio side), kept as regression tests for Master Gain on Pure. The
// founder's rule: on Pure the music is never louder than Master Gain says (what Enhanced played: the
// device's level + Master Gain; Silent = silence), the device's own level is given back, and a crash
// puts it back. Each test failed on c9efbe6.

import EQEditKit
import Foundation
import Testing

@Suite("BREAK-IT MasterGainOnPure — never louder, always given back")
struct BreakItMasterGainOnPureTests {
    private static let uid = "AppleUSBAudioEngine:DAC:1"

    @Test("a cut deeper than the device's range: Pure must not play louder than Enhanced did")
    func cutBelowTheDeviceFloor() {
        let dac = FakeVolumeDevice(level: -10, range: -40 ... 0)
        var rule = MasterGainOnPure()
        let entry = rule.enter(deviceUID: Self.uid, gain: -50, device: dac)
        // Enhanced played −10 − 50 = −60 dB. Either Pure waits, or the device reaches −60 dB.
        #expect(entry == .waitsBelowDeviceRange || dac.level <= -60,
                "Pure plays at \(dac.level) dB: 20 dB louder than Master Gain says")
    }

    @Test("Silent on Pure is silence, not the device's minimum")
    func silentIsSilence() {
        let dac = FakeVolumeDevice(level: -10, range: -40 ... 0)
        var rule = MasterGainOnPure()
        let entry = rule.enter(deviceUID: Self.uid, gain: -.infinity, device: dac)
        #expect(entry == .waitsBelowDeviceRange, "Silent engages Pure at the device's minimum (\(dac.level) dB)")
    }

    @Test("the slider below the device's floor while Pure plays: never louder than it says")
    func sliderBelowTheFloor() {
        let dac = FakeVolumeDevice(level: -15, range: -50 ... 0)
        dac.hasMute = true // a device without one holds its floor: MasterGainOnPureTests
        var rule = MasterGainOnPure()
        _ = rule.enter(deviceUID: Self.uid, gain: -10, device: dac)
        rule.gainChanged(to: -45, device: dac)
        #expect(dac.muted || dac.level <= -60, "Master Gain says −60 dB; Pure plays \(dac.level) dB")
    }

    /// The app dies the instant the HAL is asked to move the device: what the journal held then is what the
    /// next launch has (H-2). The loan is written ahead — the pending level kept before the device moves —
    /// so a crash between the two still finds Pure's level, and gives the found one back.
    @Test("crash-safe: a crash after a slider move (the tick had not kept the new loan) still gives the level back")
    func crashAfterAMove() {
        let dac = FakeVolumeDevice(level: -20)
        let journal = LoanJournal()
        var run = MasterGainOnPure(writeAhead: journal.writer)
        _ = run.enter(deviceUID: Self.uid, gain: -12, device: dac)
        var kept: [PureVolumeLoan] = []
        dac.onSet = { kept = journal.loans } // the crash: while paused, the tick sleeps — nothing else keeps it
        run.gainChanged(to: -24, device: dac)
        var nextLaunch = MasterGainOnPure(unreturned: kept)
        nextLaunch.returnUnreturned { _ in dac }
        #expect(dac.level == -20, "after the crash the device stays at \(dac.level) dB")
    }

    @Test("crash-safe: a crash before the first tick after entering Pure still gives the level back")
    func crashRightAfterEntering() {
        let dac = FakeVolumeDevice(level: -20)
        let journal = LoanJournal()
        var kept: [PureVolumeLoan] = []
        dac.onSet = { kept = journal.loans } // the crash, at Pure's first set
        var run = MasterGainOnPure(writeAhead: journal.writer)
        _ = run.enter(deviceUID: Self.uid, gain: -12, device: dac)
        dac.onSet = nil
        var nextLaunch = MasterGainOnPure(unreturned: kept)
        nextLaunch.returnUnreturned { _ in dac }
        #expect(dac.level == -20, "the device stays at \(dac.level) dB: the loan was never kept")
    }

    @Test("the listener's volume-down stands even when a slider step lands before the HAL's change notice")
    func sliderStepBeforeTheNotice() {
        let dac = FakeVolumeDevice(level: -20)
        var rule = MasterGainOnPure()
        _ = rule.enter(deviceUID: Self.uid, gain: -10, device: dac) // device −30
        dac.listenerSets(-45) // volume keys: the HAL changed, its notice still queued behind the drain
        rule.gainChanged(to: -9, device: dac) // a 1 dB slider step, drained first (same queue)
        rule.deviceChanged(gain: -9, device: dac) // then the notice
        // The listener's −45 stands, and the slider's own +1 dB step moves from it: −44, not −29 (16 dB up).
        #expect(dac.level == -44, "the listener set −45 dB; the slider step put it back to \(dac.level) dB")
    }

    @Test("a device lost mid-Pure, back in the same session and played on Enhanced, gets its level back")
    func lostDeviceBackInTheSameSession() {
        let dac = FakeVolumeDevice(level: -20)
        var rule = MasterGainOnPure()
        _ = rule.enter(deviceUID: Self.uid, gain: -12, device: dac)
        _ = rule.handle(.deviceLost) { _ in dac }
        dac.isPresent = false
        _ = rule.handle(.enhancedStarted) { _ in dac } // the speakers play: the DAC's loan goes unreturned
        dac.isPresent = true
        // The DAC is back and plays Enhanced (what production calls on that start):
        _ = rule.handle(.enhancedStarted) { _ in dac }
        #expect(dac.level == -20, "the DAC stays \(dac.level) dB, and Enhanced applies Master Gain on top")
    }
}
