// Fixtures for LevelingKit's tests: measured tracks and albums, built from numbers (no audio).

import LevelingKit

enum Fixture {
    /// The stereo roles (L, R) as the analysis records them.
    static let stereoRoles: [UInt8] = [1, 2]
    /// A 5.1 file's roles (L R C LFE Ls Rs).
    static let surroundRoles: [UInt8] = [1, 2, 3, 4, 5, 6]

    /// A stereo track measured at `loudness` LUFS and `peak` dBTP, `seconds` long, with edge blocks `head` / `tail`.
    static func stereo(_ loudness: Double?, peak: Double = -1, seconds: Double = 200, head: Double? = -20,
                       tail: Double? = -20, album: Int64? = nil) -> LevelingTrack {
        LevelingTrack(album: album, measurement: .init(
            loudness: loudness, truePeak: peak, peakRate: 48000, roles: stereoRoles, durationSeconds: seconds,
            headLoudness: head, tailLoudness: tail, folded: nil, profiles: [profile(.decoded)]
        ))
    }

    /// A 5.1 track: decoded `loudness` / `peak`, the fold at `foldLoudness` / `foldPeak` for every variant but
    /// `bump` dB louder and hotter per variant step (so the variant read is visible), the LFE rule's verdict.
    static func surround(_ loudness: Double, peak: Double, foldLoudness: Double, foldPeak: Double,
                         includes: Bool, bump: Double = 0.5, seconds: Double = 200, album: Int64? = nil,
                         head: Double? = -20, tail: Double? = -20) -> LevelingTrack {
        let steps = (0 ..< 4).map { Double($0) * bump }
        let folded = LevelingTrack.Folded(loudness: steps.map { foldLoudness + $0 },
                                          truePeak: steps.map { foldPeak + $0 }, lfeIncludes: includes)
        let profiles = [profile(.decoded)] + (0 ..< 4).map { profile(.fold(lfeVariant: $0)) }
        return LevelingTrack(album: album, measurement: .init(
            loudness: loudness, truePeak: peak, peakRate: 48000, roles: surroundRoles, durationSeconds: seconds,
            headLoudness: head, tailLoudness: tail, folded: folded, profiles: profiles
        ))
    }

    /// A one-block profile on `basis` (its contents do not matter here).
    static func profile(_ basis: CompactLoudnessProfile.Basis) -> CompactLoudnessProfile {
        CompactLoudnessProfile(basis: basis, sampleRate: 48000, bandsPerOctave: 24, bandCount: 1, blockCount: 1,
                               blockStrideHops: 1, powers: [0])
    }

    /// A library of `albums` (id → members in order) whose tracks are `tracks`, each given its album.
    static func library(_ albums: [Int64: [(String, LevelingTrack)]], loose: [String: LevelingTrack] = [:])
        -> LevelingLibrary {
        var library = LevelingLibrary(tracks: loose)
        for (album, members) in albums {
            library.albums[album] = members.map(\.0)
            for (key, track) in members {
                var member = track
                member.album = album
                library.tracks[key] = member
            }
        }
        return library
    }
}

extension TrackLevelingDecision {
    /// L as the decision states it, as decoded.
    var loudness: Double? {
        unfolded.loudness
    }
}
