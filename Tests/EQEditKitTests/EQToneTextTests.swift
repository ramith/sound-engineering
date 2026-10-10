// TONE-TEXT — the Tone copy (EQ3t; decision 24, UI plan §5.4): the five regions' names and ranges as
// the card and the graph's readout print them, their spoken forms, the level and value texts, the
// VoiceOver value with "limited", and the folded card's one line.

@testable import EQEditKit
import Testing

@Suite("Tone copy — names, ranges, levels, the folded line")
struct EQToneTextTests {
    @Test("TONE-TEXT-01: names and ranges are the design's, on the graph's own axis")
    func namesAndSpans() {
        #expect(EQToneRegion.allCases.map(\.name) == ["Bass", "Body", "Mids", "Presence", "Air"])
        #expect(EQToneRegion.allCases.map(\.span) == ["<150 Hz", "150–500 Hz", "0.5–2 kHz", "2–6 kHz", ">6 kHz"])
        #expect(EQToneRegion.allCases.map(\.spokenSpan) == [
            "below 150 hertz", "150 to 500 hertz", "500 hertz to 2 kilohertz", "2 to 6 kilohertz",
            "above 6 kilohertz",
        ])
    }

    @Test("TONE-TEXT-02: a level prints signed to a tenth; 0 prints as \"0 dB\"")
    func levels() {
        #expect(EQToneText.level(3) == "+3.0 dB")
        #expect(EQToneText.level(-4.5) == "-4.5 dB")
        #expect(EQToneText.level(0) == "0 dB")
        #expect(EQToneText.level(-0.0) == "0 dB")
        #expect(EQToneText.value(12) == "+12.0")
        #expect(EQToneText.value(-0.5) == "-0.5")
        #expect(EQToneText.value(0) == "0 dB")
    }

    @Test("TONE-TEXT-03: VoiceOver hears decibels, and \"limited\" when the ceiling holds points")
    func spokenValues() {
        #expect(EQToneText.spokenValue(3, isLimited: false) == "+3.0 decibels")
        #expect(EQToneText.spokenValue(0, isLimited: false) == "0 decibels")
        #expect(EQToneText.spokenValue(12, isLimited: true) == "+12.0 decibels, limited")
    }

    @Test("TONE-TEXT-04: the folded line — all at 0, the one region set, or how many are")
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
