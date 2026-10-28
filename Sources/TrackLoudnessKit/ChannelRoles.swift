import AudioDSP
import AVFoundation

/// The one channel-role resolver (R1.1-B, level-and-fold §S1b, M3): a file's channel roles from its labels,
/// never from position. It calls AudioDSP's `asResolveChannelRoles` (Loudness/ChannelRoles.cpp) once per file,
/// and its result goes by value to the analysis pass, the effects unit and the planner (`AsOutputState`).
///
/// - A layout tag, a channel bitmap or one description per channel (tag 0) names each slot; AAC and ALAC
///   5.1 arrive as C L R Ls Rs LFE, the FLAC 5.1 as L R C LFE Rls Rrs, and each slot gets its own label's role.
/// - A layout that names no speaker (none, DiscreteInOrder, Unknown, every label Discrete_n) or that describes
///   another count falls back to the COUNT, in WAV order (RFC 9639): the ITU and EBU signals and legacy WAVs.
///
/// The numbers are `AsChannelRole`'s (TrackPlanBridge.h), persisted with every analysis.
public enum ChannelRoles {
    /// The roles of a source with `channelCount` channels and the layout `layout` reports (`nil`: none).
    ///
    /// - Returns: one `AsChannelRole` value per channel for 1 … 8 channels; for a wider source (which plays
    ///   through the stereo fallback, never in its own layout) `AS_MAX_CHANNELS` Unknowns; none for 0.
    public static func resolve(channelCount: AVAudioChannelCount, layout: AVAudioChannelLayout?) -> [UInt8] {
        let maxChannels = AVAudioChannelCount(AS_MAX_CHANNELS)
        guard channelCount > 0 else { return [] }
        guard channelCount <= maxChannels else {
            return [UInt8](repeating: UInt8(AsChannelRoleUnknown.rawValue), count: Int(maxChannels))
        }
        var roles = [UInt8](repeating: UInt8(AsChannelRoleUnknown.rawValue), count: Int(channelCount))
        let resolved = roles.withUnsafeMutableBufferPointer { slots in
            asResolveChannelRoles(layout?.layout, UInt32(channelCount), slots.baseAddress)
        }
        assert(resolved, "1 … 8 channels always resolve")
        return roles
    }

    /// The roles of a source in `format` (its channel count and the layout it reports).
    public static func resolve(format: AVAudioFormat) -> [UInt8] {
        resolve(channelCount: format.channelCount, layout: format.channelLayout)
    }
}
