// Master Gain on Pure drives the output device's own volume (R1.1-A, founder decision 2026-10-15: "turn
// the Mac's volume down instead"; council C-29). The rule, against a fake device: has a volume or not,
// its dB range, entering / moving / leaving, the listener's own change, a device switch, and the
// crash-safe return of a loan at the next launch.

import EQEditKit
import Foundation
import Testing

/// A device the test controls: its level, its range, whether it has a volume the app can set at all,
/// whether it is there, and the steps it can actually select (real devices quantize).
final class FakeVolumeDevice: DeviceVolumeControl {
    var level: Float
    var range: ClosedRange<Float>
    var hasVolume = true
    var isPresent = true
    /// The device's step, in dB: a set lands on the nearest step.
    var step: Float = 0.5
    private(set) var sets: [Float] = []

    init(level: Float, range: ClosedRange<Float> = -64 ... 0) {
        self.level = level
        self.range = range
    }

    func read() -> DeviceVolumeReading? {
        guard isPresent, hasVolume else { return nil }
        return DeviceVolumeReading(level: level, range: range)
    }

    func set(_ decibels: Float) -> Bool {
        guard isPresent, hasVolume, decibels.isFinite else { return false }
        sets.append(decibels)
        level = min(max((decibels / step).rounded() * step, range.lowerBound), range.upperBound)
        return true
    }

    /// The listener's own change: the volume keys, Control Center, another app.
    func listenerSets(_ decibels: Float) {
        level = decibels
    }
}

@Suite("MasterGainOnPure — Master Gain on Pure is the device's own volume")
struct MasterGainOnPureTests {
    private static let uid = "AppleUSBAudioEngine:DAC:1"

    @Test("at 0 dB Pure engages and leaves the device alone, but takes the loan for a later move")
    func unityTouchesNothing() {
        let dac = FakeVolumeDevice(level: -20)
        var rule = MasterGainOnPure()
        #expect(rule.enter(deviceUID: Self.uid, gain: MasterGainLaw.unity, device: dac) == .engaged)
        #expect(dac.sets.isEmpty && dac.level == -20)
        #expect(rule.loan == PureVolumeLoan(deviceUID: Self.uid, ceiling: -20, anchor: -20, lastSet: -20))
    }

    @Test("turned down, Pure engages at once and lowers the device by Master Gain: no loudness jump")
    func turnedDownLowersTheDevice() {
        let dac = FakeVolumeDevice(level: -20)
        var rule = MasterGainOnPure()
        #expect(rule.enter(deviceUID: Self.uid, gain: -12, device: dac) == .engaged)
        #expect(dac.level == -32)
        #expect(rule.loan?.ceiling == -20 && rule.loan?.lastSet == -32)
    }

    @Test("the device's own range bounds it; Silent is the device's minimum")
    func rangeLimits() {
        let dac = FakeVolumeDevice(level: -50, range: -60 ... 0)
        var rule = MasterGainOnPure()
        _ = rule.enter(deviceUID: Self.uid, gain: -20, device: dac)
        #expect(dac.level == -60)
        rule.gainChanged(to: -.infinity, device: dac)
        #expect(dac.level == -60)
        rule.gainChanged(to: .nan, device: dac)
        #expect(dac.level == -60, "a bad level reads as Silent, the law's safe reading")
    }

    @Test("a device with no volume the app can set: turned down, Pure waits and nothing is touched")
    func noVolumeWaits() {
        let hdmi = FakeVolumeDevice(level: 0)
        hdmi.hasVolume = false
        var rule = MasterGainOnPure()
        #expect(rule.enter(deviceUID: Self.uid, gain: -6, device: hdmi) == .waitsForMasterGain)
        #expect(rule.loan == nil && hdmi.sets.isEmpty)
        #expect(rule.enter(deviceUID: Self.uid, gain: MasterGainLaw.unity, device: hdmi) == .engaged)
        #expect(rule.loan == nil, "nothing to steer, nothing to put back")
    }

    @Test("the slider moves the device from the level remembered at entry, never above it")
    func sliderMoves() {
        let dac = FakeVolumeDevice(level: -20)
        var rule = MasterGainOnPure()
        _ = rule.enter(deviceUID: Self.uid, gain: -12, device: dac)
        rule.gainChanged(to: -6, device: dac)
        #expect(dac.level == -26)
        rule.gainChanged(to: MasterGainLaw.unity, device: dac)
        #expect(dac.level == -20)
        rule.gainChanged(to: 6, device: dac)
        #expect(dac.level == -20, "never above the level Pure found")
    }

    @Test("a quantized device's own answer is not mistaken for the listener's change")
    func quantizedEcho() {
        let dac = FakeVolumeDevice(level: -20)
        dac.step = 1.5
        var rule = MasterGainOnPure()
        _ = rule.enter(deviceUID: Self.uid, gain: -12.3, device: dac)
        let landed = dac.level
        rule.deviceChanged(gain: -12.3, device: dac) // the listener fires for Pure's own set
        #expect(rule.loan?.anchor == -20 && rule.loan?.lastSet == landed)
    }

    @Test("the listener's own change stands: nothing is set, Master Gain's cut stays on top of it")
    func listenerChangeStands() {
        let dac = FakeVolumeDevice(level: -20)
        var rule = MasterGainOnPure()
        _ = rule.enter(deviceUID: Self.uid, gain: -12, device: dac) // device at -32
        dac.listenerSets(-35) // three dB down with the volume keys
        rule.deviceChanged(gain: -12, device: dac)
        #expect(dac.level == -35 && dac.sets.count == 1, "the app does not undo the change")
        #expect(rule.loan?.anchor == -23, "the listener's own level is now 3 dB lower")
        rule.gainChanged(to: -6, device: dac)
        #expect(dac.level == -29, "the slider moves from the listener's level")
        rule.leave(device: dac)
        #expect(dac.level == -23, "Pure puts back the listener's level, Master Gain then plays in the app")
    }

    @Test("turned up by the listener past where Pure found it, Pure never puts back more than it found")
    func listenerRaiseIsCapped() {
        let dac = FakeVolumeDevice(level: -20)
        var rule = MasterGainOnPure()
        _ = rule.enter(deviceUID: Self.uid, gain: -12, device: dac)
        dac.listenerSets(-10)
        rule.deviceChanged(gain: -12, device: dac)
        #expect(dac.level == -10)
        #expect(rule.loan?.anchor == -20)
        rule.leave(device: dac)
        #expect(dac.level == -20)
    }

    @Test("leaving Pure puts the remembered level back; the loan is settled")
    func leaveRestores() {
        let dac = FakeVolumeDevice(level: -20)
        var rule = MasterGainOnPure()
        _ = rule.enter(deviceUID: Self.uid, gain: -12, device: dac)
        rule.leave(device: dac)
        #expect(dac.level == -20 && rule.loan == nil && rule.unreturned.isEmpty)
    }

    @Test("a device that went away keeps its loan; when it is back, its level is put back")
    func deviceSwitch() {
        let dac = FakeVolumeDevice(level: -20)
        let speakers = FakeVolumeDevice(level: -30)
        var rule = MasterGainOnPure()
        _ = rule.enter(deviceUID: Self.uid, gain: -12, device: dac)
        dac.isPresent = false // unplugged mid-song: Pure moves to the speakers
        rule.leave(device: dac)
        #expect(rule.unreturned.map(\.deviceUID) == [Self.uid])
        #expect(rule.enter(deviceUID: "BuiltInSpeakerDevice", gain: -12, device: speakers) == .engaged)
        #expect(speakers.level == -42)

        dac.isPresent = true
        rule.returnUnreturned { uid in uid == Self.uid ? dac : nil }
        #expect(dac.level == -20 && rule.unreturned.isEmpty)
        #expect(rule.allLoans.map(\.deviceUID) == ["BuiltInSpeakerDevice"])
    }

    @Test("entering Pure on a device with a loan not yet returned puts it back first")
    func reenterReturnsFirst() {
        let dac = FakeVolumeDevice(level: -32) // lowered by a session that never put it back
        var rule = MasterGainOnPure(unreturned: [
            PureVolumeLoan(deviceUID: Self.uid, ceiling: -20, anchor: -20, lastSet: -32),
        ])
        _ = rule.enter(deviceUID: Self.uid, gain: -12, device: dac)
        #expect(dac.level == -32 && rule.loan?.ceiling == -20, "the cut is taken from the level put back")
        #expect(rule.unreturned.isEmpty)
    }

    @Test("loans a previous run left are adopted as unreturned, never over a loan already held for that device")
    func adoptKeptLoans() {
        let dac = FakeVolumeDevice(level: -20)
        var rule = MasterGainOnPure()
        _ = rule.enter(deviceUID: Self.uid, gain: -12, device: dac)
        let stale = PureVolumeLoan(deviceUID: Self.uid, ceiling: -5, anchor: -5, lastSet: -40)
        let other = PureVolumeLoan(deviceUID: "HDMI", ceiling: -10, anchor: -10, lastSet: -16)
        rule.adopt([stale, other])
        #expect(rule.loan?.ceiling == -20, "the loan held now is the truth for its device")
        #expect(rule.unreturned == [other])
        rule.adopt([other])
        #expect(rule.unreturned == [other], "adopting twice keeps one")
    }

    @Test("crash-safe: a loan kept through a crash is put back at the next launch, unless the level was changed")
    func crashSafeReturn() throws {
        let dac = FakeVolumeDevice(level: -20)
        var session = MasterGainOnPure()
        _ = session.enter(deviceUID: Self.uid, gain: -12, device: dac)
        let kept = try JSONEncoder().encode(session.allLoans) // persisted while Pure played; then the app died
        let restored = try JSONDecoder().decode([PureVolumeLoan].self, from: kept)

        var nextLaunch = MasterGainOnPure(unreturned: restored)
        nextLaunch.returnUnreturned { _ in dac }
        #expect(dac.level == -20 && nextLaunch.unreturned.isEmpty)

        // The listener changed the level after the crash: theirs stands, the loan is dropped.
        _ = session.enter(deviceUID: Self.uid, gain: -12, device: dac)
        let changed = FakeVolumeDevice(level: -40)
        var another = MasterGainOnPure(unreturned: session.allLoans)
        another.returnUnreturned { _ in changed }
        #expect(changed.level == -40 && changed.sets.isEmpty && another.unreturned.isEmpty)

        // The device isn't connected yet: the loan waits for it.
        var waiting = MasterGainOnPure(unreturned: session.allLoans)
        waiting.returnUnreturned { _ in nil as FakeVolumeDevice? }
        #expect(waiting.unreturned.count == 1)
    }
}
