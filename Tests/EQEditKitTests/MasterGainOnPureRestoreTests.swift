// VOL-RESTORED — "Volume restored" (R1.1-B, US-R1F-20 item 4): when Pure hands the device's volume back — a stop
// that ends playback, Enhanced starting, the output moving (the loan's leave; never a pause or a lost device) — and
// the level it puts back differs from the level the device was at (Master Gain had lowered it), the rule says so,
// once. When Pure touched nothing (Master Gain at 0 dB), or the listener set their own level since, it says nothing.
// Against the fake device of `MasterGainOnPureTests`.

import EQEditKit
import Foundation
import Synchronization
import Testing

@Suite("Master Gain on Pure — the level given back, told")
struct MasterGainOnPureRestoreTests {
    private static let uid = "AppleUSBAudioEngine:DAC:1"

    /// How many times the rule told of a restore.
    private final class Told: Sendable {
        private let count = Mutex(0)

        func tell() {
            count.withLock { $0 += 1 }
        }

        var times: Int {
            count.withLock { $0 }
        }
    }

    /// A rule whose restores are counted.
    private static func rule() -> (MasterGainOnPure, Told) {
        let told = Told()
        var rule = MasterGainOnPure()
        rule.onRestore = { told.tell() }
        return (rule, told)
    }

    @Test("VOL-RESTORED-01: Master Gain below 0 dB, then the end of the queue: told once, the level back",
          arguments: [PureVolumeEvent.stopped, .enhancedStarted, .outputMoved(toUID: "BuiltInSpeakerDevice")])
    func toldOnceWhenTheLevelComesBack(leaving: PureVolumeEvent) {
        let dac = FakeVolumeDevice(level: -20)
        var (rule, told) = Self.rule()
        _ = rule.enter(deviceUID: Self.uid, gain: -12, device: dac)
        #expect(dac.level == -32)
        let ended = rule.handle(leaving) { _ in dac }
        #expect(ended && dac.level == -20)
        #expect(told.times == 1)
        _ = rule.handle(.stopped) { _ in dac } // nothing held any more: nothing more to tell
        #expect(told.times == 1)
    }

    @Test("VOL-RESTORED-02: Master Gain at 0 dB — Pure touched nothing — so nothing is told")
    func silentWhenUntouched() {
        let dac = FakeVolumeDevice(level: -20)
        var (rule, told) = Self.rule()
        _ = rule.enter(deviceUID: Self.uid, gain: 0, device: dac)
        _ = rule.handle(.stopped) { _ in dac }
        #expect(dac.level == -20 && dac.sets.isEmpty)
        #expect(told.times == 0)
    }

    @Test("VOL-RESTORED-03: a pause and a lost device keep the hold — nothing told until Pure is left")
    func pauseAndLossTellNothing() {
        let dac = FakeVolumeDevice(level: -20)
        var (rule, told) = Self.rule()
        _ = rule.enter(deviceUID: Self.uid, gain: -6, device: dac)
        _ = rule.handle(.paused) { _ in dac }
        _ = rule.handle(.deviceLost) { _ in dac }
        #expect(told.times == 0 && dac.level == -26)
        _ = rule.handle(.stopped) { _ in dac }
        #expect(told.times == 1 && dac.level == -20)
    }

    /// A change the rule heard moves the anchor, so leaving lifts the cut off the listener's new level (told);
    /// one made as Pure is left, before any notice, is theirs and stands (not told).
    @Test("VOL-RESTORED-04: the listener's own change — heard, the cut is lifted off it; unheard, it stands")
    func listenersLevel() {
        let dac = FakeVolumeDevice(level: -20)
        var (rule, told) = Self.rule()
        _ = rule.enter(deviceUID: Self.uid, gain: -12, device: dac)
        dac.level = -40 // the volume keys, while Pure plays: the rule hears of it
        rule.deviceChanged(gain: -12, device: dac)
        _ = rule.handle(.stopped) { _ in dac }
        #expect(dac.level == -28, "their new level with Master Gain's cut lifted off it")
        #expect(told.times == 1)

        let other = FakeVolumeDevice(level: -20)
        var (second, quiet) = Self.rule()
        _ = second.enter(deviceUID: Self.uid, gain: -12, device: other)
        other.level = -45 // changed as Pure is left, before any notice: it is theirs, and it stands
        _ = second.handle(.stopped) { _ in other }
        #expect(other.level == -45)
        #expect(quiet.times == 0)
    }

    @Test("VOL-RESTORED-05: a mute Pure made (Silent) and given back is a level that comes back: told")
    func muteGivenBack() {
        let dac = FakeVolumeDevice(level: -20)
        dac.hasMute = true
        var (rule, told) = Self.rule()
        _ = rule.enter(deviceUID: Self.uid, gain: -.infinity, device: dac)
        #expect(dac.muted)
        _ = rule.handle(.stopped) { _ in dac }
        #expect(!dac.muted && told.times == 1)
    }

    @Test("VOL-RESTORED-06: a loan an earlier run left, put back at launch or on reappearance, is not Pure's leave")
    func returnedLoansTellNothing() {
        let dac = FakeVolumeDevice(level: -32)
        var (rule, told) = Self.rule()
        rule.adopt([PureVolumeLoan(deviceUID: Self.uid, ceiling: -20, anchor: -20, lastSet: -32)])
        rule.returnUnreturned { _ in dac }
        #expect(dac.level == -20, "the crash's loan is put back")
        #expect(told.times == 0)
    }

    @Test("VOL-RESTORED-07: a device gone when Pure is left keeps its loan, and nothing is told")
    func goneDeviceTellsNothing() {
        let dac = FakeVolumeDevice(level: -20)
        var (rule, told) = Self.rule()
        _ = rule.enter(deviceUID: Self.uid, gain: -12, device: dac)
        dac.isPresent = false
        _ = rule.handle(.stopped) { _ in dac }
        #expect(rule.unreturned.count == 1)
        #expect(told.times == 0)
    }
}
