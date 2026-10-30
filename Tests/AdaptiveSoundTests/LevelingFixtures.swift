@testable import AdaptiveSound
import AudioDSP
import Foundation
import LevelingKit
import RigKit
import Synchronization
import TrackLoudnessKit

// MARK: - What the leveling coordinator's tests feed it (R1.1-B W5, lane 3-B)

/// The leveling coordinator's sources, as a test sets them: a double provides inputs, never logic. Each file's
/// analysis (by path), tags, the library's albums, and — when `lookupHold` is set — a lookup of the store held
/// at its start until the test releases it (a slow read).
final class FakeLevelingSources: LevelingSources {
    struct State {
        /// The store's current-version records, by the file's path.
        var analyses: [String: TrackAnalysis] = [:]
        /// The saved profiles, by path and the store's basis index.
        var profiles: [String: [Int: TrackAnalysis.Profile]] = [:]
        /// The files' tags, by path.
        var tags: [String: GainTags] = [:]
        /// The library's albums: each song's (by library id), and each album's members in album order.
        var albumOfTrack: [Int64: Int64] = [:]
        var members: [Int64: [LevelingSlot]] = [:]
        /// What was asked: every store read's paths, and every profile read's path and bases.
        var analysisReads: [[String]] = []
        var profileReads: [(String, [Int])] = []
    }

    let state = Mutex(State())
    /// When set, every store read waits here first (on a thread of its own) until the test releases it.
    let lookupHold: Hold?

    init(lookupHold: Hold? = nil) {
        self.lookupHold = lookupHold
    }

    func identity(of url: URL) async -> TrackIdentity? {
        try? LevelingFixture.identity(LevelingSlot.key(of: url))
    }

    func analyses(for identities: [TrackIdentity]) async -> [TrackIdentity: TrackAnalysis] {
        if let lookupHold {
            _ = try? await blocking("leveling lookup") { lookupHold.wait() }
        }
        return state.withLock { state in
            state.analysisReads.append(identities.map(\.path).sorted())
            var found: [TrackIdentity: TrackAnalysis] = [:]
            for identity in identities {
                if let analysis = state.analyses[identity.path] {
                    found[identity] = analysis
                }
            }
            return found
        }
    }

    func profiles(for identity: TrackIdentity, bases: [Int]) async -> [Int: TrackAnalysis.Profile] {
        state.withLock { state in
            state.profileReads.append((identity.path, bases))
            return (state.profiles[identity.path] ?? [:]).filter { bases.contains($0.key) }
        }
    }

    func tags(of url: URL) async -> GainTags? {
        state.withLock { $0.tags[LevelingSlot.key(of: url)] }
    }

    func albums(of trackIDs: [Int64]) async -> [Int64: Int64] {
        state.withLock { state in state.albumOfTrack.filter { trackIDs.contains($0.key) } }
    }

    func members(ofAlbum album: Int64) async -> [LevelingSlot] {
        state.withLock { $0.members[album] ?? [] }
    }
}

/// The analysis store's records and the files' identities, built the way the store keeps them (Codable: the
/// record's own initialiser is TrackLoudnessKit's).
enum LevelingFixture {
    /// A file's identity at `path`.
    static func identity(_ path: String) throws -> TrackIdentity {
        try JSONDecoder().decode(TrackIdentity.self, from: JSONSerialization.data(withJSONObject: [
            "path": path, "size": 1000, "modified": 1.0,
        ]))
    }

    /// The LFE statistics of an independent LFE (bass the mains do not carry: the rule includes it) and of a copy
    /// of the mains' bass (the rule omits it) — lane 2's rule's own cases (§5).
    static var independentLfe: [String: Any] {
        [
            "activeBlocks": 400, "lagMs": 0.0, "lagPeak": 0.1, "coherentShare": 0.0, "medianR2": 0.05, "p90R2": 0.1,
            "excess20Share": 0.9, "explainGainDb": 2.0,
        ]
    }

    static var copiedLfe: [String: Any] {
        [
            "activeBlocks": 400, "lagMs": 0.0, "lagPeak": 0.95, "coherentShare": 0.99, "medianR2": 0.95, "p90R2": 0.99,
            "excess20Share": 0.0, "explainGainDb": 1.0,
        ]
    }

    /// The record of the file at `path`: stereo, or a 5.1 fold (with `lfe`'s statistics).
    static func analysis(_ path: String, loudness: Double?, truePeak: Double?, head: Double? = -20,
                         tail: Double? = -20, surround: Bool = false,
                         lfe: [String: Any] = ["activeBlocks": 0]) throws -> TrackAnalysis {
        let none = NSNull()
        let roles: [Int] = surround ? [1, 2, 3, 4, 5, 6] : [1, 2]
        let folded: [Any] = surround ? [-14.0, -13.5, -12.8, -11.9] : [none, none, none, none]
        let foldedPeaks: [Any] = surround ? [-1.5, -1.2, -0.8, -0.2] : [none, none, none, none]
        let object: [String: Any] = [
            "version": 1, "identity": ["path": path, "size": 1000, "modified": 1.0],
            "channelCount": roles.count, "roles": roles, "sourceRateHz": 48000.0, "peakRateHz": 48000.0,
            "durationSeconds": 200.0, "integratedLufs": loudness ?? none, "truePeakDbtp": truePeak ?? none,
            "headBlockLufs": head ?? none, "tailBlockLufs": tail ?? none, "folds": surround,
            "foldedLufs": folded, "foldedTruePeakDbtp": foldedPeaks, "lfe": lfe,
            "histograms": [[Any]](repeating: [], count: Int(AS_PROFILE_BASES)),
            "profiles": [Any](repeating: none, count: Int(AS_PROFILE_BASES)), "analysedAt": 0.0,
        ]
        return try JSONDecoder().decode(TrackAnalysis.self, from: JSONSerialization.data(withJSONObject: object))
    }

    /// A saved profile (its powers the given value, a few blocks).
    static func profile(_ value: UInt16 = 0x3C00) throws -> TrackAnalysis.Profile {
        try JSONDecoder().decode(TrackAnalysis.Profile.self, from: JSONSerialization.data(withJSONObject: [
            "sampleRate": 48000.0, "bandsPerOctave": 24, "bandCount": 2, "blockCount": 2, "blockStrideHops": 1,
            "powers": [value, value, value, value],
        ] as [String: Any]))
    }
}
