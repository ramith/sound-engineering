// R1.1-A (founder decision 2026-10-14, KI-SND-05): crossfeed plays on its own, so the hero shows it
// whenever it plays — Intensity 0 included. On the real `SignalPathInfo`.

@testable import AdaptiveSound
import Foundation
import SettingsKit
import Testing

@MainActor
@Suite("Crossfeed — where it plays, and what the hero shows", .serialized)
struct CrossfeedPlaysTests {
    @Test("the hero shows crossfeed whenever it plays — Intensity 0 included — and never on Pure")
    func heroShowsAudibleCrossfeed() {
        var info = SignalPathInfo()
        info.intensityLinear = 0
        info.crossfeedStrength = .strong
        #expect(info.audibleCrossfeed == .strong, "crossfeed plays at Intensity 0, so the chip shows")
        info.intensityLinear = 0.5
        #expect(info.audibleCrossfeed == .strong)
        info.path = .pure
        #expect(info.audibleCrossfeed == nil, "Pure bypasses the DSP: no crossfeed plays")
        info.path = .enhanced
        info.crossfeedStrength = nil
        #expect(info.audibleCrossfeed == nil, "off, or not on headphones")
        #expect(!SignalPathAccessibility.value(for: info).contains("crossfeed"))
        info.crossfeedStrength = .relaxed
        #expect(SignalPathAccessibility.value(for: info).contains("crossfeed Relaxed"))
    }
}
