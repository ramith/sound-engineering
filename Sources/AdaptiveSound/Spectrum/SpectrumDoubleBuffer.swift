// SpectrumDoubleBuffer.swift
//
// Lock-free pair of Float arrays for audio-thread → main-thread data handoff.

import Accelerate
import Foundation
import Synchronization

// MARK: - Lock-free Double Buffer

/// A pair of Float arrays swapped via a generation counter.
/// The producer (audio thread) writes into the "back" slot; increments
/// the counter when done. The consumer (main thread) reads the slot
/// whose index matches the latest counter.
///
/// Safety: both slots are pre-allocated at init. No allocation ever
/// occurs in `write(_:)` or `read(into:)`.
///
/// `@unchecked Sendable` invariant: this is a single-producer/single-consumer (SPSC)
/// lock-free handoff. `write(_:)` is called ONLY from the audio tap thread (the sole
/// writer); `read(into:)` is called ONLY from the MainActor (the sole reader). Both
/// `slots` are pre-sized at `init` and NEVER reallocated — they are only overwritten
/// in place via `withUnsafeMutableBufferPointer`. Cross-thread ORDERING is carried by the
/// `publishedGeneration` atomic: the writer RELEASE-stores it AFTER filling the slot and the
/// reader ACQUIRE-loads it BEFORE copying the slot out — so a reader that observes the new
/// generation is guaranteed to see the fully-written slot (no torn frame). No lock or queue
/// is ever taken on either side; adding one would put synchronization on the RT writer
/// (priority-inversion risk) — forbidden. This is the actual RT→UI boundary, so an
/// audited `@unchecked Sendable` is the correct tool here.
final class SpectrumDoubleBuffer: @unchecked Sendable {
    private let count: Int
    private var slots: [[Float]] // [slot0, slot1]
    private var generation: Int = 0 // audio-thread-local write counter (sole writer)

    /// The last-published generation — the SPSC seam. RELEASE-stored by the writer AFTER the slot
    /// copy, ACQUIRE-loaded by the reader BEFORE its copy, so the slot write happens-before the
    /// reader's read whenever the reader observes the new value (no torn frame). Matches the C++ RT
    /// snapshot's named-atomic acquire/release. `Atomic` is from the stdlib `Synchronization` module
    /// (macOS 15+; the package targets macOS 26).
    private let publishedGeneration = Atomic<Int>(-1)

    /// Generation the reader last copied out. Accessed ONLY on the main thread (the sole reader),
    /// so it needs no cross-thread synchronization. Lets `read(into:)` honour its documented "new
    /// data since the last call?" contract and lets the 20 Hz UI skip redundant work when the tap
    /// has not published a fresh frame (e.g. while paused / idle). (F2)
    private var lastConsumedGeneration: Int = -1

    init(count: Int) {
        self.count = count
        slots = [
            [Float](repeating: 0, count: count),
            [Float](repeating: 0, count: count),
        ]
    }

    /// Audio thread: copy `values` into the next slot and publish.
    /// No allocation. No lock.
    func write(_ values: UnsafeBufferPointer<Float>) {
        precondition(values.count == count)
        let nextSlot = (generation + 1) & 1
        slots[nextSlot].withUnsafeMutableBufferPointer { dst in
            guard let dstBase = dst.baseAddress,
                  let srcBase = values.baseAddress else { return }
            // Straight contiguous copy (was cblas_scopy stride-1); non-allocating.
            dstBase.update(from: srcBase, count: count)
        }
        generation = generation &+ 1 // wrapping add; sole writer on audio thread
        // RELEASE: publish the slot copy above before the new generation becomes visible.
        publishedGeneration.store(generation, ordering: .releasing)
    }

    /// Main thread: copy the latest published slot into `out`.
    /// Returns `true` if new data was available since the last call.
    @discardableResult
    func read(into out: inout [Float]) -> Bool {
        // ACQUIRE: pair with the writer's release so the slot copy below is fully visible.
        let gen = publishedGeneration.load(ordering: .acquiring)
        guard gen >= 0 else { return false }
        // No frame published since the last read → nothing new to copy (F2: the return value now
        // honestly means "new data", so callers can skip redundant UI work).
        guard gen != lastConsumedGeneration else { return false }
        lastConsumedGeneration = gen
        let slot = gen & 1
        out.withUnsafeMutableBufferPointer { dst in
            slots[slot].withUnsafeBufferPointer { src in
                guard let dstBase = dst.baseAddress, let srcBase = src.baseAddress else { return }
                // Straight contiguous copy (was cblas_scopy stride-1); non-allocating.
                dstBase.update(from: srcBase, count: count)
            }
        }
        return true
    }
}
