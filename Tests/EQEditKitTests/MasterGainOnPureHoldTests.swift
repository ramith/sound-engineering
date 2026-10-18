// Master Gain on Pure (R1.1-A): how long Pure holds a device's volume (founder decision 2026-10-16 — a
// pause keeps it, leaving Pure gives it back), a damaged kept loan (close-out break-it SET-4), and what is
// given back (H-4). The fake device and the core rule's tests: MasterGainOnPureTests.

import EQEditKit
import Foundation
import Testing

@Suite("MasterGainOnPure — the hold, and what is given back")
struct MasterGainOnPureHoldTests {
    private static let uid = "AppleUSBAudioEngine:DAC:1"

    // MARK: - The hold lasts while Pure is this device's path (founder decision 2026-10-16)

    /// The engine's devices, by UID.
    private static func devices(_ list: [String: FakeVolumeDevice]) -> (String) -> FakeVolumeDevice {
        { uid in list[uid] ?? FakeVolumeDevice(level: 0) }
    }

    @Test("pause and resume in Pure never touch the device's volume")
    func pauseKeepsTheLevel() {
        let dac = FakeVolumeDevice(level: -20)
        var rule = MasterGainOnPure()
        _ = rule.enter(deviceUID: Self.uid, gain: -12, device: dac) // lowered to -32: one set
        let ended1 = rule.handle(.paused, device: Self.devices([Self.uid: dac]))
        #expect(!ended1, "a pause is not leaving Pure")
        #expect(dac.level == -32 && dac.sets.count == 1)
        let resumed = rule.enter(deviceUID: Self.uid, gain: -12, device: dac)
        #expect(resumed == .engaged)
        #expect(dac.level == -32 && dac.sets.count == 1)

        // The listener's own change while paused is still theirs.
        dac.listenerSets(-35)
        rule.deviceChanged(gain: -12, device: dac)
        _ = rule.handle(.paused, device: Self.devices([Self.uid: dac]))
        _ = rule.enter(deviceUID: Self.uid, gain: -12, device: dac)
        #expect(dac.level == -35 && dac.sets.count == 1, "never undone, not even on resume")
    }

    @Test("leaving Pure gives the level back once: a stop, or Enhanced starting")
    func leavingGivesItBackOnce() {
        for leaving in [PureVolumeEvent.stopped, .enhancedStarted] {
            let dac = FakeVolumeDevice(level: -20)
            var rule = MasterGainOnPure()
            _ = rule.enter(deviceUID: Self.uid, gain: -12, device: dac)
            _ = rule.handle(.paused, device: Self.devices([Self.uid: dac]))
            let ended2 = rule.handle(leaving, device: Self.devices([Self.uid: dac]))
            #expect(ended2)
            #expect(dac.level == -20 && dac.sets.count == 2 && rule.loan == nil)
            let ended3 = rule.handle(.stopped, device: Self.devices([Self.uid: dac]))
            #expect(!ended3, "nothing left to give back")
            #expect(dac.sets.count == 2)
        }
    }

    @Test("the output moving to another device gives the level back on the old one")
    func outputMovedGivesBackTheOldDevice() {
        let dac = FakeVolumeDevice(level: -20)
        var rule = MasterGainOnPure()
        _ = rule.enter(deviceUID: Self.uid, gain: -12, device: dac)
        _ = rule.handle(.paused, device: Self.devices([Self.uid: dac]))
        let ended4 = rule.handle(.outputMoved(toUID: Self.uid), device: Self.devices([Self.uid: dac]))
        #expect(!ended4)
        #expect(dac.level == -32, "the same device: still Pure's")
        let ended5 = rule.handle(.outputMoved(toUID: "BuiltInSpeakerDevice"), device: Self.devices([Self.uid: dac]))
        #expect(ended5)
        #expect(dac.level == -20 && rule.loan == nil)
    }

    @Test("a lost device keeps the hold: nothing is asked of a dying device, its loan is not lost")
    func deviceLostKeepsTheHold() {
        let dac = FakeVolumeDevice(level: -20)
        var rule = MasterGainOnPure()
        _ = rule.enter(deviceUID: Self.uid, gain: -12, device: dac)
        dac.isPresent = false
        let ended6 = rule.handle(.deviceLost, device: Self.devices([Self.uid: dac]))
        #expect(!ended6)
        #expect(rule.allLoans.map(\.deviceUID) == [Self.uid])
        // Quit with the device still gone: the loan stays out, kept for the next launch.
        let ended7 = rule.handle(.stopped, device: Self.devices([Self.uid: dac]))
        #expect(ended7)
        #expect(rule.unreturned.map(\.deviceUID) == [Self.uid])
    }

    // MARK: - A damaged loan (R1.1-A close-out break-it, SET-4)

    @Test("a damaged loan never puts the device back above what Pure found, and never sends a non-number",
          arguments: [
              ("anchor above the ceiling", Float(0), Float(-30), Float(-40)),
              ("NaN anchor", .nan, -30, -40), ("+∞ anchor", .infinity, -30, -40), ("−∞ anchor", -.infinity, -30, -40),
              ("NaN ceiling", -30, .nan, -40), ("+∞ ceiling", -30, .infinity, -40), ("NaN lastSet", -30, -30, .nan),
          ])
    func damagedLoanIsNeverLouder(what: String, anchor: Float, ceiling: Float, lastSet: Float) {
        let dac = FakeVolumeDevice(level: lastSet.isFinite ? lastSet : -40) // reads what Pure last set
        let loan = PureVolumeLoan(deviceUID: Self.uid, ceiling: ceiling, anchor: anchor, lastSet: lastSet)
        var rule = MasterGainOnPure(unreturned: [loan])
        rule.returnUnreturned { _ in dac }
        #expect(dac.sets.allSatisfy { $0.isFinite }, "\(what): a non-number reached the device")
        let found = min(anchor.isFinite ? anchor : -.infinity, ceiling.isFinite ? ceiling : -.infinity)
        #expect(dac.sets.allSatisfy { $0 <= max(found, -40) }, "\(what): set to \(dac.sets), above what Pure found")
        #expect(rule.unreturned.isEmpty, "\(what): a damaged loan is dropped, not kept out forever")
        #expect(!loan.isSound || what == "anchor above the ceiling")
    }

    /// Some interfaces run above 0 dB (+6, +12). Pure's lowering stays turn-down only, but what it gives
    /// back is what it found — within the device's own range, not clamped to 0 dB (H-4).
    @Test("a device found above 0 dB gets that level back, not 0 dB")
    func foundAboveZeroIsGivenBack() {
        let interface = FakeVolumeDevice(level: 6, range: -64 ... 12)
        var rule = MasterGainOnPure()
        _ = rule.enter(deviceUID: Self.uid, gain: -10, device: interface)
        #expect(interface.level == -4)
        let ended = rule.handle(.stopped) { _ in interface }
        #expect(ended && interface.level == 6, "given back at \(interface.level) dB")
    }
}
