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
}
