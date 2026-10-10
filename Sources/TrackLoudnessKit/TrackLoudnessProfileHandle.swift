import AudioDSP

/// One owned reference to an immutable track loudness profile (`AsLoudnessProfile`,
/// TrackLoudnessBridge.h): a prefix or the whole track. Released on deinit. The C-ABI makes a
/// profile safe to read from any thread at once, and the engine keeps its own reference when one
/// is published, so a handle may be cached, shared and dropped freely.
public final class TrackLoudnessProfileHandle: @unchecked Sendable {
    // @unchecked: the pointer is immutable after init and the profile behind it is immutable and
    // documented thread-safe for reads (TrackLoudnessBridge.h, THREADS).

    /// The borrowed `const AsLoudnessProfile*` for a C-ABI call.
    public let pointer: OpaquePointer
    /// The profile's metadata (rate, analysed seconds, blocks, whether it is the whole track).
    public let info: AsLoudnessProfileInfo

    /// Take ownership of `pointer` (from asLoudnessProfilerFinishPrefix / FinishFull); nil for a
    /// NULL one.
    init?(taking pointer: OpaquePointer?) {
        guard let pointer else { return nil }
        var info = AsLoudnessProfileInfo()
        guard asLoudnessProfileGetInfo(pointer, &info) else {
            asLoudnessProfileDestroy(pointer)
            return nil
        }
        self.pointer = pointer
        self.info = info
    }

    deinit {
        asLoudnessProfileDestroy(pointer)
    }

    /// The bytes the profile holds (its band powers), for the analyzer's cache budget.
    var bytes: Int {
        Int(info.blockCount) * Int(info.bandCount) * MemoryLayout<Float>.size
    }
}
