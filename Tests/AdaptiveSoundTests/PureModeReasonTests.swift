// Pure honesty (R1.1-A, council C-34, C-33): the one named reason Pure isn't playing bit-perfect, or
// isn't playing — decoded from the engine's codes (PureModeBridge.h), and the words the UI shows for it:
// a short note beside the Now Playing badge, a sentence in Settings ▸ Pure Mode (and the note's tooltip),
// and what VoiceOver reads.

@testable import AdaptiveSound
import Testing

@Suite("PureModeReason — the one named reason, and its words")
struct PureModeReasonTests {
    @Test("the engine's codes decode to their reasons, in PureModeBridge.h's order; 0 and 1 are bit-perfect")
    func codes() {
        #expect(PureModeReason(code: 0) == nil)
        #expect(PureModeReason(code: 1) == nil)
        #expect(PureModeReason(code: 2) == .bluetooth)
        #expect(PureModeReason(code: 3) == .virtualDevice)
        #expect(PureModeReason(code: 4) == .rateUnsupported)
        #expect(PureModeReason(code: 5) == .channelCountMismatch)
        #expect(PureModeReason(code: 6) == .notBitPerfect)
        #expect(PureModeReason(code: 7) == .deviceWouldNotStart)
        #expect(PureModeReason(code: 8) == .fileUnreadable)
        #expect(PureModeReason(code: 9) == .needsFFmpeg)
        #expect(PureModeReason(code: 200) == nil, "a code this build doesn't know names nothing")
    }

    @Test("Pure plays only when the depth is the reason; every other reason means Enhanced plays")
    func whoPlays() {
        for reason in PureModeReason.allCases {
            #expect(reason.purePlays == (reason == .notBitPerfect))
            var info = SignalPathInfo()
            info.pureReason = reason
            #expect(info.fellBackToEnhanced == !reason.purePlays)
        }
        #expect(!SignalPathInfo().fellBackToEnhanced)
    }

    @Test("every reason has a short note for the badge and a sentence that says what plays")
    func words() {
        var info = SignalPathInfo()
        info.sourceBitDepth = 24
        info.bitDepth = 16
        for reason in PureModeReason.allCases {
            #expect(!reason.note.isEmpty && reason.note.count <= 24, "\(reason): '\(reason.note)'")
            let sentence = reason.detail(in: info, masterGain: -12)
            #expect(sentence.hasSuffix("."), "\(reason): '\(sentence)'")
        }
        #expect(PureModeReason.bluetooth.note == "Pure off: Bluetooth")
        #expect(PureModeReason.needsFFmpeg.note == "Pure off: needs FFmpeg")
        #expect(PureModeReason.notBitPerfect.note == "Not bit-perfect")
        #expect(PureModeReason.waitsForMasterGain.note == "Pure waits: Master Gain")
        #expect(PureModeReason.masterGainBelowDeviceRange.note == "Pure waits: device range")
    }

    @Test("C-33: the depth sentence names both depths; the Master Gain one names the level")
    func sentencesCarryTheirNumbers() {
        var info = SignalPathInfo()
        info.sourceBitDepth = 24
        info.bitDepth = 16
        let depth = PureModeReason.notBitPerfect.detail(in: info, masterGain: 0)
        #expect(depth.contains("24-bit") && depth.contains("16-bit"))
        #expect(depth.contains("with dither"), "a 16-bit word: Pure reduces with TPDF dither (2026-10-16)")
        info.sourceBitDepth = 32
        info.bitDepth = 32
        info.isFloat = true
        #expect(!PureModeReason.notBitPerfect.detail(in: info, masterGain: 0).contains("dither"),
                "a float output has no integer step to dither")
        let waits = PureModeReason.waitsForMasterGain.detail(in: info, masterGain: -12)
        #expect(waits.contains("-12.0 dB"))
        let belowRange = PureModeReason.masterGainBelowDeviceRange.detail(in: info, masterGain: -50)
        #expect(belowRange.contains("-50.0 dB") && belowRange.contains("Enhanced"), "H-1: says why, and what plays")
        #expect(PureModeReason.needsFFmpeg.detail(in: info, masterGain: 0).contains("FFmpeg"))
    }

    @Test("VoiceOver reads the reason, not a generic 'unavailable'")
    func spoken() {
        var info = SignalPathInfo()
        info.achievedSampleRate = 44100
        info.pureReason = .bluetooth
        #expect(SignalPathAccessibility.value(for: info).hasSuffix("Pure off: Bluetooth"))
        info.path = .pure
        info.pureReason = .notBitPerfect
        #expect(SignalPathAccessibility.value(for: info).hasSuffix("Not bit-perfect"))
    }
}
