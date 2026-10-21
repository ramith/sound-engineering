// R1.1-A (council C-51; panel P1 D56, KI-ENG-01): the analyser hands each frame to the main thread
// whole. The tap thread writes a frame while the main thread copies the last one; before R1.1 a
// two-slot buffer let the writer lap the reader mid-copy (1 033 torn frames in 160 984 reads, and a
// ThreadSanitizer data race). The writer here cycles three frames — every value 1, then 2, then 3,
// so no slot always gets the same one — and a copy that mixes two shows at once. The frames are long
// and the reader is slow mid-read on purpose (its copy target is shared, so each read first copies
// it), as a preempted or stalled main thread would be. The run is judged by COUNTS, not a window of
// time: it goes on until the reader has seen enough frames AND enough of those reads overlapped a
// completed write (the writer lapped the reader mid-read, witnessed by the writer's own write count
// moving across the read) — so a slow machine only runs longer, and a run that never overlapped fails
// saying so instead of passing vacuously.

@testable import AdaptiveSound
import Foundation
import RigKit
import Synchronization
import Testing

@Suite("The analyser's hand-off never tears a frame (C-51)", .timeLimit(.minutes(3)))
struct SpectrumHandoffTests {
    /// What the writer thread publishes for the reader to witness.
    private final class WriterState: Sendable {
        let stop = Atomic<Bool>(false)
        /// Whole frames written so far.
        let writes = Atomic<Int>(0)
    }

    /// What the reader saw.
    private struct Seen: Sendable {
        var reads = 0
        var overlapped = 0
        var torn = 0
    }

    /// Long frames: each copy takes long enough for the writer to be inside one.
    private static let frameSize = 4096
    /// Frames the reader must see, and how many of those reads must have overlapped a write.
    private static let readsWanted = 2000
    private static let overlapsWanted = 50
    /// A ceiling in iterations (not time): a reader that spins this long without the counts has failed.
    private static let iterationCeiling = 200_000_000

    @Test("a reader racing a writer that never pauses only ever copies whole frames")
    func noTornFrames() async throws {
        let count = Self.frameSize
        let handoff = SpectrumTripleBuffer(count: count)
        let writer = WriterState()
        let writing = Task {
            try await blocking("spectrum-writer") {
                let frames = (1 ... 3).map { [Float](repeating: Float($0), count: count) }
                while !writer.stop.load(ordering: .relaxed) {
                    for frame in frames {
                        frame.withUnsafeBufferPointer { handoff.write($0) }
                        writer.writes.add(1, ordering: .releasing)
                    }
                }
            }
        }
        let seen = try await blocking("spectrum-reader") { () -> Seen in
            var copy = [Float](repeating: 0, count: count)
            var seen = Seen()
            var iterations = 0
            while seen.reads < Self.readsWanted || seen.overlapped < Self.overlapsWanted, iterations < Self.iterationCeiling {
                iterations += 1
                let shared = copy // the read must copy `copy` before it writes into it: a slow read
                let before = writer.writes.load(ordering: .acquiring)
                if handoff.read(into: &copy) {
                    seen.reads += 1
                    if writer.writes.load(ordering: .acquiring) != before {
                        seen.overlapped += 1
                    }
                    if copy.contains(where: { $0 != copy[0] }) {
                        seen.torn += 1
                    }
                }
                _ = shared.count
            }
            return seen
        }
        writer.stop.store(true, ordering: .relaxed)
        try await writing.value
        #expect(seen.reads >= Self.readsWanted, "the reader saw only \(seen.reads) new frames")
        #expect(seen.overlapped >= Self.overlapsWanted,
                "only \(seen.overlapped) of \(seen.reads) reads overlapped a write: the race never happened")
        #expect(seen.torn == 0, "\(seen.torn) of \(seen.reads) frames were torn")
    }
}
