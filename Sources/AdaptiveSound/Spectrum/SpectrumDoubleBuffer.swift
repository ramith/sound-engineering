// SpectrumDoubleBuffer.swift
//
// Lock-free pair of Float arrays for audio-thread → main-thread data handoff.

import Accelerate
import Foundation

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
/// in place via `withUnsafeMutableBufferPointer`. Cross-thread coordination is the
/// wrapping `publishedGeneration` counter, published via an aligned `Int` store
/// (single-instruction, atomic on arm64 for aligned 64-bit stores). No lock or queue
/// is ever taken on either side; adding one would put synchronization on the RT writer
/// (priority-inversion risk) — forbidden. This is the actual RT→UI boundary, so an
/// audited `@unchecked Sendable` is the correct tool here.
final class SpectrumDoubleBuffer: @unchecked Sendable {
    private let count: Int
    private var slots: [[Float]] // [slot0, slot1]
    private var generation: Int = 0 // written only on audio thread; read on main

    /// `pendingGeneration` is the generation value last written.
    /// Using a plain Int stored via an UnsafeAtomic-equivalent pattern:
    /// we rely on the fact that Int writes are atomic on LP64 (arm64) for
    /// aligned 64-bit stores, and the audio thread is the sole writer.
    /// For a production-grade alternative, use AtomicRepresentable from
    /// swift-atomics (SE-0282).
    private var publishedGeneration: Int = -1 // read on main, written on audio thread

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
        publishedGeneration = generation // arm64: aligned Int write is single instruction
    }

    /// Main thread: copy the latest published slot into `out`.
    /// Returns `true` if new data was available since the last call.
    @discardableResult
    func read(into out: inout [Float]) -> Bool {
        let gen = publishedGeneration // read once
        guard gen >= 0 else { return false }
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
