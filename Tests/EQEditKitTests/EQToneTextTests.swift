// TONE-TEXT — the EQ's words (EQ3t; decision 24, UI plan §5.4): the five regions' names and spans, which
// the Tone card and the graph's labels share; how a level is written and spoken everywhere
// (`EQLevelText`); the graph's Tone readout; a Tone slider's VoiceOver value; the folded card's line.

@testable import EQEditKit
import Testing

@Suite("EQ words — region names, levels, the Tone readout, the folded line")
struct EQToneTextTests {
    @Test("TONE-TEXT-01: one set of region names and spans, on the graph's own axis")
    func namesAndSpans() {
        #expect(EQToneRegion.allCases.map(\.name) == ["Bass", "Body", "Mids", "Presence", "Air"])
        #expect(EQToneRegion.allCases.map(\.span) == ["<150 Hz", "150–500 Hz", "0.5–2 kHz", "2–6 kHz", ">6 kHz"])
        #expect(EQToneRegion.allCases.map(\.spokenSpan) == [
            "below 150 hertz", "150 to 500 hertz", "500 hertz to 2 kilohertz", "2 to 6 kilohertz",
            "above 6 kilohertz",
        ])
        // The spans the graph labels over: crossover to crossover, the open ends running to the axis's.
        #expect(EQToneRegion.allCases.map(\.spanHz) == [
            20 ... 150, 150 ... 500, 500 ... 2000, 2000 ... 6000, 6000 ... 20000,
        ])
        // Each span holds its own region's full weight at its (log) middle — the label sits on its region.
        for region in EQToneRegion.allCases {
            let middle = (region.spanHz.lowerBound * region.spanHz.upperBound).squareRoot()
            #expect(region.weight(atHz: middle) > 0.5, "\(region) at \(middle) Hz")
        }
    }

    @Test("TONE-TEXT-02: a level is signed to a tenth — with its unit, without, and spoken")
    func levels() {
        #expect(EQLevelText.level(4) == "+4.0 dB")
        #expect(EQLevelText.level(-2.5) == "-2.5 dB")
        #expect(EQLevelText.level(0) == "0.0 dB")
        #expect(EQLevelText.number(12) == "+12.0")
        #expect(EQLevelText.number(-0.5) == "-0.5")
        #expect(EQLevelText.number(0) == "0.0")
        #expect(EQLevelText.number(-0.0) == "0.0", "never \"-0.0\"")
        #expect(EQLevelText.number(-0.04) == "0.0", "a level that rounds to zero is a plain 0")
        #expect(EQLevelText.spoken(4) == "plus 4 decibels")
        #expect(EQLevelText.spoken(-2.5) == "minus 2.5 decibels")
        #expect(EQLevelText.spoken(0) == "0 decibels")
    }

    @Test("TONE-TEXT-03: the graph's Tone readout, with the points the ceiling holds")
    func readout() {
        #expect(EQToneText.readout(.presence, db: 3, heldPoints: 0) == "Tone · Presence 2–6 kHz +3.0 dB")
        #expect(EQToneText.readout(.bass, db: -2.5, heldPoints: 1) == "Tone · Bass <150 Hz -2.5 dB · 1 point held")
        #expect(EQToneText.readout(.air, db: 12, heldPoints: 3) == "Tone · Air >6 kHz +12.0 dB · 3 points held")
    }

    @Test("TONE-TEXT-04: VoiceOver hears decibels, and \"limited\" when the ceiling holds points")
    func spokenValues() {
        #expect(EQToneText.spokenValue(3, isLimited: false) == "plus 3 decibels")
        #expect(EQToneText.spokenValue(0, isLimited: false) == "0 decibels")
        #expect(EQToneText.spokenValue(12, isLimited: true) == "plus 12 decibels, limited")
    }

    @Test("TONE-TEXT-05: the folded line — all at 0, the one region set, or how many are")
    func foldedSummary() {
        var curve = EQCurve(points: EQBuiltInPreset.warm.points)
        #expect(EQToneText.summary(of: curve) == "all at 0 dB")
        curve.setTone(.presence, to: 3)
        #expect(EQToneText.summary(of: curve) == "Presence +3.0 dB")
        curve.setTone(.bass, to: -1.5)
        curve.setTone(.air, to: 2)
        #expect(EQToneText.summary(of: curve) == "3 regions set")
        curve.resetTone()
        #expect(EQToneText.summary(of: curve) == "all at 0 dB")
    }
}
