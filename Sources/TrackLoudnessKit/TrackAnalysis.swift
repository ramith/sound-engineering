import AudioDSP
import Foundation

/// What the one analysis pass measured of a track (R1.1-B, level-and-fold §1.2 and §S1): the Swift mirror of
/// `AsTrackAnalysis` (TrackLoudnessBridge.h), plus what the store keeps beside it — the file's identity, the
/// gated-loudness histograms, the persisted −ΔL profiles and when it was analysed. Codable, so the analysis
/// store (lane 3) can persist it; a value of another `version` counts as not analysed.
///
/// "Not measured" is `nil` (the C struct's NaN): no gated block, no fold, no LFE. Every per-basis array has
/// `AS_PROFILE_BASES` entries — 0 as decoded, 1 + v the BS.775 fold at LFE variant v — and the fold arrays
/// `AS_FOLD_LFE_VARIANTS`, empty or nil where the file has no fold.
public struct TrackAnalysis: Codable, Sendable, Equatable {
    /// The LFE statistics (`AsLfeStats`); the LFE rule (FoldLfeRule) decides from them at plan time.
    public struct LfeStatistics: Codable, Sendable, Equatable {
        public var activeBlocks: Int
        public var lagMs: Double?
        public var lagPeak: Double?
        public var coherentShare: Double?
        public var medianR2: Double?
        public var p90R2: Double?
        public var excess20Share: Double?
        public var explainGainDb: Double?

        /// The C form the LFE rule reads (NaN for nil).
        public var stats: AsLfeStats {
            AsLfeStats(activeBlocks: UInt32(clamping: activeBlocks), lagMs: Float(lagMs ?? .nan),
                       lagPeak: Float(lagPeak ?? .nan), coherentShare: Float(coherentShare ?? .nan),
                       medianR2: Float(medianR2 ?? .nan), p90R2: Float(p90R2 ?? .nan),
                       excess20Share: Float(excess20Share ?? .nan), explainGainDb: Float(explainGainDb ?? .nan))
        }
    }

    /// One non-empty bin of a gated-loudness histogram (`AsLoudnessBin`): 0.1 LU from −70 LUFS.
    public struct LoudnessBin: Codable, Sendable, Equatable {
        public var bin: UInt32
        public var count: UInt32
        public var energy: Double
    }

    /// A persisted −ΔL profile (`AsCompactProfileInfo` + its binary16 band powers, block-major).
    public struct Profile: Codable, Sendable, Equatable {
        public var sampleRate: Double
        public var bandsPerOctave: Int
        public var bandCount: Int
        public var blockCount: Int
        public var blockStrideHops: Int
        public var powers: [UInt16]

        /// The C form `asLoudnessProfileFromCompact` reads.
        public var info: AsCompactProfileInfo {
            AsCompactProfileInfo(sampleRate: sampleRate, bandsPerOctave: UInt32(clamping: bandsPerOctave),
                                 bandCount: UInt32(clamping: bandCount), blockCount: UInt32(clamping: blockCount),
                                 blockStrideHops: UInt32(clamping: blockStrideHops))
        }
    }

    /// `AS_TRACK_ANALYSIS_VERSION` when measured.
    public var version: Int
    public var identity: TrackIdentity
    public var channelCount: Int
    /// `AsChannelRole` per channel (the one resolver's, as fed to the analyzer).
    public var roles: [UInt8]
    /// The file's own rate, and the rate its true peaks were measured at (the engine's).
    public var sourceRateHz: Double
    public var peakRateHz: Double
    public var durationSeconds: Double
    /// L_N (LUFS) and TP_N (dBTP; −200 for digital silence).
    public var integratedLufs: Double?
    public var truePeakDbtp: Double?
    /// The first and last whole 400 ms block (LUFS), for the continuity judge.
    public var headBlockLufs: Double?
    public var tailBlockLufs: Double?
    /// Whether the fold was measured (N > 2).
    public var folds: Bool
    /// L_F[v] and TP_F[v], one per LFE variant.
    public var foldedLufs: [Double?]
    public var foldedTruePeakDbtp: [Double?]
    public var lfe: LfeStatistics
    /// Per basis (`AS_PROFILE_BASES`): the histogram's non-empty bins, and the persisted profile.
    public var histograms: [[LoudnessBin]]
    public var profiles: [Profile?]
    public var analysedAt: Date
}

extension TrackAnalysis {
    /// The mirror of a finished analysis (`analysis`), with what the analyzer holds beside it.
    init(_ analysis: AsTrackAnalysis, analyzer: OpaquePointer, identity: TrackIdentity, sourceRateHz: Double,
         analysedAt: Date) {
        let channels = Int(analysis.channelCount)
        let bases = Int(AS_PROFILE_BASES)
        self.init(version: Int(analysis.version), identity: identity, channelCount: channels,
                  roles: Self.values(of: analysis.roles, count: channels),
                  sourceRateHz: sourceRateHz, peakRateHz: analysis.peakRateHz,
                  durationSeconds: analysis.durationSeconds,
                  integratedLufs: Self.measured(analysis.integratedLufs),
                  truePeakDbtp: Self.measured(analysis.truePeakDbtp),
                  headBlockLufs: Self.measured(analysis.headBlockLufs),
                  tailBlockLufs: Self.measured(analysis.tailBlockLufs),
                  folds: analysis.folds != 0,
                  foldedLufs: Self.values(of: analysis.foldedLufs, count: Int(AS_FOLD_LFE_VARIANTS)).map(Self.measured),
                  foldedTruePeakDbtp: Self.values(of: analysis.foldedTruePeakDbtp, count: Int(AS_FOLD_LFE_VARIANTS))
                      .map(Self.measured),
                  lfe: LfeStatistics(analysis.lfe),
                  histograms: (0 ..< bases).map { Self.histogram(analyzer, basis: UInt8($0)) },
                  profiles: (0 ..< bases).map { Self.profile(analyzer, basis: UInt8($0)) },
                  analysedAt: analysedAt)
    }

    private static func measured(_ value: Double) -> Double? {
        value.isNaN ? nil : value
    }

    /// The first `count` elements of a C array (imported as a homogeneous tuple).
    private static func values<Tuple, Element>(of tuple: Tuple, count: Int) -> [Element] {
        withUnsafeBytes(of: tuple) { Array($0.bindMemory(to: Element.self).prefix(count)) }
    }

    private static func histogram(_ analyzer: OpaquePointer, basis: UInt8) -> [LoudnessBin] {
        let count = asTrackAnalyzerHistogram(analyzer, basis, nil, 0)
        var bins = [AsLoudnessBin](repeating: AsLoudnessBin(), count: Int(count))
        let written = bins.withUnsafeMutableBufferPointer {
            asTrackAnalyzerHistogram(analyzer, basis, $0.baseAddress, count)
        }
        return written == count ? bins.map { LoudnessBin(bin: $0.bin, count: $0.count, energy: $0.energy) } : []
    }

    private static func profile(_ analyzer: OpaquePointer, basis: UInt8) -> Profile? {
        var info = AsCompactProfileInfo()
        guard asTrackAnalyzerProfileInfo(analyzer, basis, &info) else { return nil }
        let count = asTrackAnalyzerProfile(analyzer, basis, nil, 0)
        var powers = [UInt16](repeating: 0, count: Int(count))
        let written = powers.withUnsafeMutableBufferPointer {
            asTrackAnalyzerProfile(analyzer, basis, $0.baseAddress, count)
        }
        guard written == count else { return nil }
        return Profile(sampleRate: info.sampleRate, bandsPerOctave: Int(info.bandsPerOctave),
                       bandCount: Int(info.bandCount), blockCount: Int(info.blockCount),
                       blockStrideHops: Int(info.blockStrideHops), powers: powers)
    }
}

extension TrackAnalysis.LfeStatistics {
    init(_ stats: AsLfeStats) {
        func measured(_ value: Float) -> Double? {
            value.isNaN ? nil : Double(value)
        }
        self.init(activeBlocks: Int(stats.activeBlocks), lagMs: measured(stats.lagMs), lagPeak: measured(stats.lagPeak),
                  coherentShare: measured(stats.coherentShare), medianR2: measured(stats.medianR2),
                  p90R2: measured(stats.p90R2), excess20Share: measured(stats.excess20Share),
                  explainGainDb: measured(stats.explainGainDb))
    }
}

extension TrackAnalysis {
    /// An album's POOLED loudness (§3, the ReplayGain / libebur128 `global_multiple` anchor): BS.1770's gates over
    /// every block of `members` on `basis` (0 as decoded, 1 + v the fold at LFE variant v), from their
    /// histograms (`asLoudnessPoolHistograms`). nil when no block passes the gates.
    public static func pooledLufs(_ members: [TrackAnalysis], basis: Int) -> Double? {
        let lists = members.map { member -> [AsLoudnessBin] in
            guard member.histograms.indices.contains(basis) else { return [] }
            return member.histograms[basis].map { AsLoudnessBin(bin: $0.bin, count: $0.count, energy: $0.energy) }
        }
        let counts = lists.map { UInt32($0.count) }
        let pooled = Self.withPointers(to: lists) { pointers in
            counts.withUnsafeBufferPointer { asLoudnessPoolHistograms(pointers, $0.baseAddress, UInt32(lists.count)) }
        }
        return pooled.isNaN ? nil : pooled
    }

    /// `body` with one stable pointer per list.
    private static func withPointers<Result>(to lists: [[AsLoudnessBin]],
                                             _ body: (UnsafePointer<UnsafePointer<AsLoudnessBin>?>?) -> Result)
        -> Result {
        var pointers: [UnsafePointer<AsLoudnessBin>?] = []
        func nest(_ index: Int) -> Result {
            guard index < lists.count else {
                return pointers.withUnsafeBufferPointer { body($0.baseAddress) }
            }
            return lists[index].withUnsafeBufferPointer { list in
                pointers.append(list.baseAddress)
                return nest(index + 1)
            }
        }
        return nest(0)
    }
}
