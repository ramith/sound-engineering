// R1.1-A (council C-51; panel P1 D56, KI-ENG-01): the analyser hands each frame to the main thread
// whole. The tap thread writes a frame while the main thread copies the last one; before R1.1 a
// two-slot buffer let the writer lap the reader mid-copy (1 033 torn frames in 160 984 reads, and a
// ThreadSanitizer data race). The writer here cycles three frames — every value 1, then 2, then 3,
// so no slot always gets the same one — and a copy that mixes two shows at once. The frames are long
// and the reader is slow mid-read on purpose (its copy target is shared, so each read first copies
// it), as a preempted or stalled main thread would be: a lap that can happen does, within the
// test's second (about one read in ten tore on the two-slot buffer).

@testable import AdaptiveSound
import Foundation
import Synchronization
import Testing

@Suite("The analyser's hand-off never tears a frame (C-51)")
struct SpectrumHandoffTests {
    /// Tells the writer thread to stop.
    private final class StopFlag: Sendable {
        let raised = Atomic<Bool>(false)
    }

    /// Long frames: each copy takes long enough for the writer to be inside one.
    private static let frameSize = 4096

    @Test("a reader racing a writer that never pauses only ever copies whole frames")
    func noTornFrames() {
        let count = Self.frameSize
        let handoff = SpectrumTripleBuffer(count: count)
        let stop = StopFlag()
        let writer = Thread {
            let frames = (1 ... 3).map { [Float](repeating: Float($0), count: count) }
            while !stop.raised.load(ordering: .relaxed) {
                for frame in frames {
                    frame.withUnsafeBufferPointer { handoff.write($0) }
                }
            }
        }
        writer.start()
        var copy = [Float](repeating: 0, count: count)
        var reads = 0
        var torn = 0
        let deadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < deadline {
            let shared = copy // the read must copy `copy` before it writes into it: a slow read
            if handoff.read(into: &copy) {
                reads += 1
                if copy.contains(where: { $0 != copy[0] }) {
                    torn += 1
                }
            }
            _ = shared.count
        }
        stop.raised.store(true, ordering: .relaxed)
        #expect(reads > 100, "the reader saw only \(reads) new frames")
        #expect(torn == 0, "\(torn) of \(reads) frames were torn")
    }
}
