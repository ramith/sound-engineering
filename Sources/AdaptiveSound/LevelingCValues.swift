import AudioDSP
import Foundation
import LevelingKit

// MARK: - The leveling values in the planner's C-ABI (R1.1-B, level-and-fold §S3)

//
// What the bridge's leveling (`AudioEngineBridge+Leveling`) hands the C++ planner and the effects unit, built from
// the app's values: a decision's C mirror (`AsTrackLeveling`), the output state (`AsOutputState`), and a saved −ΔL
// profile rebuilt for the engine (`SavedLoudnessProfile`).

/// A saved compact −ΔL profile rebuilt for the engine (`asLoudnessProfileFromCompact`, C2): one owned reference,
/// released on deinit. Immutable; the C-ABI makes a profile safe to read from any thread.
final class SavedLoudnessProfile: @unchecked Sendable {
    // @unchecked: the pointer is immutable after init and the profile behind it immutable and documented
    // thread-safe for reads (TrackLoudnessBridge.h, THREADS).

    let basis: CompactLoudnessProfile.Basis
    let pointer: OpaquePointer

    /// The engine's profile of `compact`; nil when it cannot be rebuilt (another grid, a short payload).
    init?(_ compact: CompactLoudnessProfile) {
        var info = AsCompactProfileInfo()
        info.sampleRate = compact.sampleRate
        info.bandsPerOctave = UInt32(clamping: compact.bandsPerOctave)
        info.bandCount = UInt32(clamping: compact.bandCount)
        info.blockCount = UInt32(clamping: compact.blockCount)
        info.blockStrideHops = UInt32(clamping: compact.blockStrideHops)
        let made = compact.powers.withUnsafeBufferPointer { powers in
            asLoudnessProfileFromCompact(&info, powers.baseAddress, UInt32(clamping: powers.count))
        }
        guard let made else { return nil }
        basis = compact.basis
        pointer = made
    }

    deinit {
        asLoudnessProfileDestroy(pointer)
    }
}

extension AsOutputState {
    /// The output before the graph has said otherwise: the engine's 48 kHz, stereo in and out, transport unknown.
    static var unknownStereo: AsOutputState {
        var state = AsOutputState()
        state.engineRateHz = 48000
        state.sourceChannels = 2
        state.outputChannels = 2
        state.sourceRoles.0 = UInt8(AsChannelRoleL.rawValue)
        state.sourceRoles.1 = UInt8(AsChannelRoleR.rawValue)
        return state
    }

    /// The same output, field by field.
    func isSame(as other: AsOutputState) -> Bool {
        var (left, right) = (sourceRoles, other.sourceRoles)
        let rolesMatch = withUnsafeBytes(of: &left) { lhs in withUnsafeBytes(of: &right) { lhs.elementsEqual($0) } }
        return transportType == other.transportType && engineRateHz == other.engineRateHz
            && sourceChannels == other.sourceChannels && outputChannels == other.outputChannels && rolesMatch
    }
}

extension AsTrackLeveling {
    /// The decision's C mirror (TrackPlanBridge.h): NaN for every unknown number.
    init(_ decision: TrackLevelingDecision) {
        self.init()
        mode = switch decision.mode {
        case .off: UInt8(AsLevelingModeOff.rawValue)
        case .leveled: UInt8(AsLevelingModeLeveled.rawValue)
        case .unknownCut: UInt8(AsLevelingModeUnknownCut.rawValue)
        }
        source = switch decision.source {
        case .analysis: UInt8(AsLevelingSourceAnalysis.rawValue)
        case .tags: UInt8(AsLevelingSourceTags.rawValue)
        case .unknownCut: UInt8(AsLevelingSourceUnknownCut.rawValue)
        }
        continuousWithPrevious = decision.continuousWithPrevious ? 1 : 0
        let measuredRoles = Array(decision.roles.prefix(Int(AS_MAX_CHANNELS)))
        channelCount = UInt8(measuredRoles.count)
        Self.fill(&roles, with: measuredRoles, count: Int(AS_MAX_CHANNELS),
                  padding: UInt8(AsChannelRoleUnknown.rawValue))
        peakRateHz = decision.peakRate ?? 0
        loudnessLufs = decision.unfolded.loudness ?? .nan
        truePeakDbtp = decision.unfolded.truePeak ?? .nan
        let variants = Int(AS_FOLD_LFE_VARIANTS)
        if let folded = decision.folded {
            hasFolded = 1
            lfeVariant = UInt8(clamping: max(0, min(folded.variant, variants - 1)))
        }
        Self.fill(&foldedLufs, with: decision.folded?.loudness ?? [], count: variants, padding: .nan)
        Self.fill(&foldedTruePeakDbtp, with: decision.folded?.truePeak ?? [], count: variants, padding: .nan)
    }

    /// Fill the C array `tuple` (`count` elements of `Element`) from `values`, `padding` past their end.
    private static func fill<Tuple, Element>(_ tuple: inout Tuple, with values: [Element], count: Int,
                                             padding: Element) {
        precondition(MemoryLayout<Tuple>.size == count * MemoryLayout<Element>.stride, "not a C array of Element")
        withUnsafeMutablePointer(to: &tuple) { pointer in
            pointer.withMemoryRebound(to: Element.self, capacity: count) { elements in
                for index in 0 ..< count {
                    elements[index] = values.indices.contains(index) ? values[index] : padding
                }
            }
        }
    }
}
