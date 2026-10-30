@testable import AdaptiveSound
import AppKit
import DesignTokenKit
import SettingsKit
import SwiftUI
import Testing

// MARK: - The hero's badge row holds by structure (R1.1-B fix round, F4: review-ui M2)

//
// The hero's text column is 414 pt wide at the 880 pt minimum window and 474 pt at the default 1000 pt (it and the
// lens split what the insets and the gap leave). A surround file folded to stereo while Pure is declined for a
// reason the fold badge doesn't carry — Bluetooth (the founder's XM4 with Pure on), FFmpeg, a virtual output, a
// device that refused, Master Gain — put four chips on the row, about 525 pt: the row was squeezed, its reason
// truncated to "P…" and its format chip cut. A stereo file on Bluetooth with crossfeed playing is four chips too.
// The row must degrade by structure (the reason to its glyph, then the format chip to its rate, each on its
// tooltip; the reason in words in VoiceOver's value), never be squeezed: offered the hero's width, it is laid out
// at one of its levels whole — that level's own natural width, within the width offered.

@MainActor
@Suite("The hero's badge row never squeezes (M2)", .timeLimit(.minutes(1)))
struct SignalBadgeRowTests {
    /// The hero text column's width at the 880 pt minimum window and at the default 1000 pt one: the hero and the
    /// lens split what the insets and the gap leave, the lens held to 400…560 pt (`HeroRow`) — 414 and 474 pt.
    private static let heroWidths: [CGFloat] = [880, 1000].map { window in
        let shared = window - 2 * NowPlayingLayout.contentInset - NowPlayingLayout.regionGap
        let lens = min(max(shared / 2, NowPlayingLayout.lensMinWidth), NowPlayingLayout.lensMaxWidth)
        return CGFloat(shared - lens)
    }

    /// A 5.1 file folded to stereo on its first, unmeasured play ("5.1 → stereo · measuring"), 48 kHz.
    private static func folded(declinedFor reason: PureModeReason?) -> SignalPathInfo {
        var info = SignalPathInfo()
        info.achievedSampleRate = 48000
        info.fold = FoldState(sourceChannels: 6, outputChannels: 2, fromPlan: true, trimDb: -8.9, lfeGain: 0,
                              backstopPeakGrDb: 0)
        info.leveling = LevelingReadout(mode: .unknownCut, gainDb: -6.3, foldMeasured: false, sourceLayout: "5.1")
        info.crossfeedStrength = .defaultStrength
        info.crossfeedEngaged = false // crossfeed is bypassed on a fold
        info.pureReason = reason
        return info
    }

    /// A stereo file on Bluetooth headphones with crossfeed playing, Pure asked for: "XF" and the reason.
    private static func stereoOnBluetooth() -> SignalPathInfo {
        var info = SignalPathInfo()
        info.achievedSampleRate = 44100
        info.crossfeedStrength = .strong
        info.crossfeedEngaged = true
        info.pureReason = .bluetooth
        return info
    }

    private static func row(_ info: SignalPathInfo) -> SignalBadgeRow {
        SignalBadgeRow(info: info, masterGain: -6, format: "FLAC", isPlaying: true, reduceMotion: true,
                       badgeHeight: CGFloat(GlassDecor.badgeBaseHeight))
    }

    /// `view`'s width when offered `width` (2000: its natural width).
    private static func width(of view: some View, offered width: CGFloat = 2000) -> CGFloat {
        NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 200)).width
    }

    /// Offered `width`, the row is laid out at one of its levels whole — within `width`, and at that level's own
    /// natural width (a squeezed row is narrower than its words and wider than its glyph). Returns the level shown.
    private static func expectWhole(_ info: SignalPathInfo, offered width: CGFloat, _ what: String,
                                    sourceLocation: SourceLocation = #_sourceLocation) -> SignalBadgeLevel? {
        let row = row(info)
        let laidOut = Self.width(of: row, offered: width)
        let levels = SignalBadgeLevel.allCases.map { ($0, Self.width(of: row.badges($0))) }
        let shown = levels.first { abs($0.1 - laidOut) < 0.5 }
        #expect(laidOut <= width && shown != nil,
                "\(what) at \(width) pt: laid out at \(laidOut) pt; its levels are \(levels) — squeezed",
                sourceLocation: sourceLocation)
        return shown?.0
    }

    @Test("BADGES-01: a fold with Pure declined for any reason but channels: the row degrades, never squeezes",
          arguments: PureModeReason.allCases.filter { $0 != .channelCountMismatch && $0 != .notBitPerfect })
    func foldWithAnotherReasonNeverSqueezes(reason: PureModeReason) {
        let info = Self.folded(declinedFor: reason)
        #expect(Self.width(of: Self.row(info).badges(.full)) > Self.heroWidths[1],
                "every word doesn't fit even the 1000 pt hero: the case needs a level")
        for width in Self.heroWidths {
            #expect(Self.expectWhole(info, offered: width, "\(reason)") != .full)
        }
    }

    @Test("BADGES-02: a stereo file on Bluetooth with crossfeed playing and Pure asked for: never squeezed")
    func crossfeedAndReasonNeverSqueeze() {
        for width in Self.heroWidths {
            _ = Self.expectWhole(Self.stereoOnBluetooth(), offered: width, "XF and Pure off: Bluetooth")
        }
    }

    @Test("BADGES-03: the rows that fit keep every word: the fold carrying the channels reason, and no reason")
    func rowsThatFitKeepTheirWords() {
        for info in [Self.folded(declinedFor: .channelCountMismatch), Self.folded(declinedFor: nil)] {
            #expect(Self.expectWhole(info, offered: Self.heroWidths[0], "the three-chip fold row") == .full)
        }
    }
}
