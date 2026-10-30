import AudioDSP
import LevelingKit
import SettingsKit
import TrackLoudnessKit

// MARK: - The leveling boundary (R1.1-B W5, lane 3-B; level-and-fold §S3)

//
// LevelingKit imports nothing, so the app converts what TrackLoudnessKit stores and reads into the Kit's own values
// here, in one place: the analysis store's record (`TrackAnalysis`) into a `LevelingTrack.Measurement` — with the
// LFE rule's verdict computed by AudioDSP's `asFoldDecideLfe`, lane 2's rule, from the record's statistics, so its
// thresholds tune without re-analysis (M4) — each persisted profile (`TrackAnalysis.Profile`) into a
// `CompactLoudnessProfile`, and the tag reader's raw values (`TrackGainTags`) into a `GainTags`.

extension TrackAnalysis {
    /// The analysis in the decision builder's terms. `profiles`: the saved profiles loaded for it, by the store's
    /// basis index (0 as decoded, 1 + v the fold at LFE variant v) — any subset; the builder keeps the ones its
    /// decision plays.
    func levelingMeasurement(profiles: [Int: TrackAnalysis.Profile] = [:]) -> LevelingTrack.Measurement {
        LevelingTrack.Measurement(
            loudness: integratedLufs, truePeak: truePeakDbtp, peakRate: peakRateHz, roles: roles,
            durationSeconds: durationSeconds, headLoudness: headBlockLufs, tailLoudness: tailBlockLufs,
            folded: folds ? LevelingTrack.Folded(loudness: foldedLufs, truePeak: foldedTruePeakDbtp,
                                                 lfeIncludes: lfe.ruleIncludes) : nil,
            profiles: profiles.sorted { $0.key < $1.key }.compactMap { basis, profile in
                CompactLoudnessProfile.Basis(storeIndex: basis).map(profile.compact(basis:))
            }
        )
    }
}

extension TrackAnalysis.LfeStatistics {
    /// Whether the fold plays this track's LFE: the LFE rule's verdict on its stored statistics (lane 2's
    /// `asFoldDecideLfe`; under 5 s of active LFE, or no LFE at all, is "omit").
    var ruleIncludes: Bool {
        var stats = stats
        return asLfeVerdictIncludes(asFoldDecideLfe(&stats))
    }
}

extension TrackAnalysis.Profile {
    /// The profile as LevelingKit carries it, on `basis`. The fields are the same; only the type differs.
    func compact(basis: CompactLoudnessProfile.Basis) -> CompactLoudnessProfile {
        CompactLoudnessProfile(basis: basis, sampleRate: sampleRate, bandsPerOctave: bandsPerOctave,
                               bandCount: bandCount, blockCount: blockCount, blockStrideHops: blockStrideHops,
                               powers: powers)
    }
}

extension CompactLoudnessProfile.Basis {
    /// The basis the store numbers `index` (`AS_PROFILE_BASES`: 0 as decoded, 1 + v the fold at LFE variant v), or
    /// nil past the last.
    init?(storeIndex index: Int) {
        switch index {
        case 0: self = .decoded
        case 1 ..< Int(AS_PROFILE_BASES): self = .fold(lfeVariant: index - 1)
        default: return nil
        }
    }

    /// The store's index for this basis.
    var storeIndex: Int {
        switch self {
        case .decoded: 0
        case let .fold(lfeVariant): 1 + lfeVariant
        }
    }
}

extension GainTags {
    /// The tag reader's raw values, field for field (the −18 LUFS conversion is the Kit's). Nil when the file
    /// carries none.
    init?(_ tags: TrackGainTags) {
        guard !tags.isEmpty else { return nil }
        self.init(replayGainTrack: tags.replayGainTrack, replayGainTrackPeak: tags.replayGainTrackPeak,
                  replayGainAlbum: tags.replayGainAlbum, replayGainAlbumPeak: tags.replayGainAlbumPeak,
                  r128Track: tags.r128Track, r128Album: tags.r128Album)
    }
}

extension LevelingMode {
    /// The Kit's mode for the listener's setting (`ListeningSettings.leveling`): the same four, by name.
    init(_ setting: LevelingSetting) {
        self = switch setting {
        case .off: .off
        case .auto: .auto
        case .album: .album
        case .track: .track
        }
    }
}
