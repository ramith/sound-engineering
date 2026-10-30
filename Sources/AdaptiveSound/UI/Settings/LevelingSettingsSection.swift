import EQEditKit
import LevelingKit
import SettingsKit
import SwiftUI

/// The Leveling card (R1.1-B, US-R1F-10 items 1–2; the row lives in Settings — founder, 2026-10-25): Off / Auto /
/// Album / Track on the title row, what the choice does in one plain sentence, the target, and — while a song is
/// loaded and Leveling is on — the gain it plays at and where its loudness came from. In Pure the switch is inert
/// and the card reads "Leveling off (bit-perfect)", with Leave Pure (US-R1F-20).
struct LevelingSettingsSection: View {
    @Bindable var audioViewModel: AudioViewModel

    var body: some View {
        let availability = audioViewModel.dspRowAvailability
        SettingsCard(title: "Leveling") {
            CapsuleSwitch("Leveling", selection: $audioViewModel.leveling, options: LevelingSetting.allCases,
                          title: LevelingRowText.title)
                .fixedSize()
                .bitPerfectGate(.leveling, availability)
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                Text(LevelingRowText.meaning(of: audioViewModel.leveling))
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(DesignSystem.Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                status(availability)
            }
            BitPerfectRowNote(row: .leveling, availability: availability, leavePure: audioViewModel.leavePure)
        }
    }

    /// "Target −18 LUFS", and the song playing's gain and source, on one line read as one.
    @ViewBuilder
    private func status(_ availability: DSPRowAvailability) -> some View {
        let now = availability.isLive
            ? LevelingRowText.nowPlaying(setting: audioViewModel.leveling, readout: songReadout,
                                         source: audioViewModel.levelingState.playing?.decision.source)
            : nil
        Text([LevelingRowText.target, now?.text].compactMap(\.self).joined(separator: " · "))
            .font(DesignSystem.Font.caption.monospaced())
            .foregroundStyle(DesignSystem.Color.labelTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel([LevelingRowText.spokenTarget, now?.spoken].compactMap(\.self).joined(separator: ", "))
    }

    /// The engine's plan for the song loaded, if one is.
    private var songReadout: LevelingReadout? {
        audioViewModel.selectedTrackIndex == nil ? nil : audioViewModel.signalPath.leveling
    }
}

// MARK: - The words

/// The Leveling card's words, as one pure function of what it shows (tested on their own).
enum LevelingRowText {
    /// The target, shown on the row (US-R1F-10 item 2); not settable.
    static let target = "Target −18 LUFS"
    static let spokenTarget = "Target minus 18 LUFS"

    /// A choice's title on the switch.
    static func title(_ setting: LevelingSetting) -> String {
        switch setting {
        case .off: "Off"
        case .auto: "Auto"
        case .album: "Album"
        case .track: "Track"
        }
    }

    /// What the choice does, in plain words.
    static func meaning(of setting: LevelingSetting) -> String {
        switch setting {
        case .off:
            "Songs play as they were recorded."
        case .auto:
            "An album played in order keeps its own balance; songs from different albums each play at one level."
        case .album:
            "Each album plays at one level, its loudest song at the target, so its quiet songs stay quiet."
        case .track:
            "Each song plays at the target on its own; songs that run into each other share one level."
        }
    }

    /// The song playing's line: the gain its plan plays at and where its loudness came from — nil with Leveling
    /// Off, or no leveled plan yet.
    static func nowPlaying(setting: LevelingSetting, readout: LevelingReadout?,
                           source: TrackLevelingDecision.Source?) -> (text: String, spoken: String)? {
        guard setting != .off, let readout, readout.mode != .off else { return nil }
        let gain = Float(readout.gainDb)
        let from: String? = readout.mode == .unknownCut ? "loudness unknown" : sourceWords(source)
        let tail = from.map { ", \($0)" } ?? ""
        return ("This song \(EQLevelText.level(gain))" + tail, "This song \(EQLevelText.spoken(gain))" + tail)
    }

    /// Where a leveled song's loudness came from.
    private static func sourceWords(_ source: TrackLevelingDecision.Source?) -> String? {
        switch source {
        case .analysis: "from analysis"
        case .tags: "from file tags"
        case .unknownCut: "loudness unknown"
        case nil: nil
        }
    }
}
