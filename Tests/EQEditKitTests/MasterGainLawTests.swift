// MASTER-GAIN — the Master Gain's law (S10.8 G, break-it G-GAIN-1; founder decision 2026-10-12, "Show
// the real level"): slider position, dB and the linear gain that plays are one mapping; turn-down
// only, 0 dB at the top, dB-linear over 60 dB with a silent bottom stop; the readout writes the level
// that plays.

import EQEditKit
import Foundation
import Testing

@Suite("Master Gain — one law for position, dB, linear gain and the readout")
struct MasterGainLawTests {
    @Test("MASTER-GAIN-01: the top is unity (the default), the bottom stop is silence")
    func ends() {
        #expect(MasterGainLaw.unity == 0)
        #expect(MasterGainLaw.decibels(position: 1) == 0)
        #expect(MasterGainLaw.linearGain(decibels: MasterGainLaw.unity) == 1, "the default plays untouched")
        #expect(MasterGainLaw.decibels(position: 0) == -.infinity)
        #expect(MasterGainLaw.linearGain(decibels: -.infinity) == 0)
        #expect(MasterGainLaw.position(decibels: 0) == 1)
        #expect(MasterGainLaw.position(decibels: -.infinity) == 0)
    }

    @Test("MASTER-GAIN-02: the travel is linear in dB — every step is 1 dB, down to one step above silence")
    func taper() {
        // The grid a drag snaps to and a key moves by: 60 steps, 1 dB each.
        #expect(abs(MasterGainLaw.step * 60 - 1) < 1e-6)
        for stepIndex in 1 ... 60 {
            let position = Float(stepIndex) * MasterGainLaw.step
            let expected = -Float(60 - stepIndex)
            #expect(abs(MasterGainLaw.decibels(position: position) - expected) < 1e-4, "step \(stepIndex)")
        }
        // The middle of the slider is −30 dB — not the −6 dB a linear-amplitude slider puts there.
        #expect(abs(MasterGainLaw.decibels(position: 0.5) + 30) < 1e-4)
        // Quietest audible stop: one step above the bottom, −59 dB; the floor itself is only approached.
        #expect(MasterGainLaw.decibels(position: MasterGainLaw.step) > MasterGainLaw.floorDecibels)
    }

    @Test("MASTER-GAIN-03: position and dB round-trip; levels past either end sit at that end")
    func inverse() {
        for db: Float in [0, -0.5, -3, -12.25, -30, -59] {
            let back = MasterGainLaw.decibels(position: MasterGainLaw.position(decibels: db))
            #expect(abs(back - db) < 1e-4, "\(db) dB")
        }
        // A device's own volume can sit above 0 dB or below the floor: the knob pins, the readout tells.
        #expect(MasterGainLaw.position(decibels: 6) == 1)
        #expect(MasterGainLaw.position(decibels: -60) == 0)
        #expect(MasterGainLaw.position(decibels: -96) == 0)
        // Out-of-range positions clamp to the travel.
        #expect(MasterGainLaw.decibels(position: 1.5) == 0)
        #expect(MasterGainLaw.decibels(position: -0.2) == -.infinity)
    }

    @Test("MASTER-GAIN-04: the linear gain is 10^(dB/20) and never boosts")
    func linear() {
        #expect(abs(MasterGainLaw.linearGain(decibels: -6.0206) - 0.5) < 1e-4)
        #expect(abs(MasterGainLaw.linearGain(decibels: -20) - 0.1) < 1e-6)
        #expect(abs(MasterGainLaw.linearGain(decibels: -60) - 0.001) < 1e-7)
        // Turn-down only: a level above 0 dB still plays at unity.
        #expect(MasterGainLaw.linearGain(decibels: 6) == 1)
        // Monotonic along the travel: a step up is never quieter.
        var previous: Float = -1
        for stepIndex in 0 ... 60 {
            let gain = MasterGainLaw.linearGain(
                decibels: MasterGainLaw.decibels(position: Float(stepIndex) * MasterGainLaw.step)
            )
            #expect(gain > previous, "step \(stepIndex)")
            previous = gain
        }
    }

    @Test("MASTER-GAIN-05: a bad value is silence, never a blast")
    func badValues() {
        #expect(MasterGainLaw.linearGain(decibels: .nan) == 0)
        #expect(MasterGainLaw.position(decibels: .nan) == 0)
        #expect(MasterGainLaw.decibels(position: .nan) == -.infinity)
        #expect(MasterGainLaw.text(.nan) == "Silent")
    }

    @Test("MASTER-GAIN-06: the readout and VoiceOver say the level that plays")
    func words() {
        #expect(MasterGainLaw.text(0) == "0.0 dB")
        #expect(MasterGainLaw.text(-3.1) == "-3.1 dB")
        #expect(MasterGainLaw.text(-59) == "-59.0 dB")
        #expect(MasterGainLaw.text(2) == "+2.0 dB", "a device's own volume above 0 dB is shown as it is")
        #expect(MasterGainLaw.text(-.infinity) == "Silent")
        #expect(MasterGainLaw.spoken(0) == "0 decibels")
        #expect(MasterGainLaw.spoken(-3.1) == "minus 3.1 decibels")
        #expect(MasterGainLaw.spoken(-.infinity) == "silent")
        // The slider's own grid prints clean whole dB (no float dust such as "-3.0000002").
        #expect(MasterGainLaw.text(MasterGainLaw.decibels(position: 57 * MasterGainLaw.step)) == "-3.0 dB")
    }
}
