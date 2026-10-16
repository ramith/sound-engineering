// SpectrumTripleBuffer.swift
//
// The analyser's frame hand-off, tap thread → main thread (council C-51, D56; KI-ENG-01).

import Synchronization

// MARK: - Wait-free SPSC triple buffer

/// Hands frames of `count` floats from ONE producer (an analyser's tap thread) to ONE consumer (the
/// main thread), whole. It is the C++ RT snapshot's design (`DoubleBufferSnapshot.h`, whose proof
/// it follows) in Swift: three slots and one atomic control word holding the READY slot's index and
/// a FRESH bit, which each side swaps with a single `exchange`.
///
/// At every instant the producer's slot, the consumer's slot and the ready slot are three different
/// slots: a publish swaps the producer's with the ready one, a fresh read swaps the consumer's with
/// it, and a swap of two in a permutation leaves a permutation. So each copy runs on a slot no other
/// thread touches, and a frame is never torn, however slow either side is. (The two-slot buffer it
/// replaces let a writer lap a slow reader and overwrite the slot mid-copy.) Both exchanges are
/// acquire-release: a slot travels both ways, so each side releases its own copy to the other (the
/// C++ proof's (5)). No lock, no allocation, no retry; ThreadSanitizer models every edge.
///
/// `@unchecked Sendable`: the slot memory is plain, its ownership handed over by the control word
/// as above. Each side's slot index is that side's alone — a relaxed atomic only so the tap thread
/// runs no exclusivity check.
final class SpectrumTripleBuffer: @unchecked Sendable {
    /// Floats per frame.
    let count: Int

    /// Three slots of `count` floats, back to back; allocated once, never moved.
    private let slots: UnsafeMutablePointer<Float>
    /// The ready slot's index (bits 0–1) and the fresh bit: a frame published since the last read.
    private let control = Atomic<Int>(2)
    /// The slot the producer writes next.
    private let producerSlot = Atomic<Int>(0)
    /// The slot the consumer holds: the last frame it took.
    private let consumerSlot = Atomic<Int>(1)

    private static let indexMask = 0b011
    private static let freshBit = 0b100

    init(count: Int) {
        self.count = count
        slots = .allocate(capacity: 3 * count)
        slots.initialize(repeating: 0, count: 3 * count)
    }

    deinit {
        slots.deallocate()
    }

    /// Producer (the tap thread): publish `values` — exactly `count` floats — as the newest frame.
    /// Wait-free: one copy into the producer's own slot, one exchange.
    func write(_ values: UnsafeBufferPointer<Float>) {
        precondition(values.count == count)
        guard let source = values.baseAddress else { return }
        let slot = producerSlot.load(ordering: .relaxed)
        (slots + slot * count).update(from: source, count: count)
        // Install the written slot as the ready one, take back the slot it replaces.
        let previous = control.exchange(slot | Self.freshBit, ordering: .acquiringAndReleasing)
        producerSlot.store(previous & Self.indexMask, ordering: .relaxed)
    }

    /// Consumer (the main thread): copy the newest frame into `out` (its first `count` values), if
    /// one was published since the last call. Returns whether there was one. Wait-free.
    @discardableResult
    func read(into out: inout [Float]) -> Bool {
        guard control.load(ordering: .acquiring) & Self.freshBit != 0 else { return false }
        // Claim the ready slot, hand back the one held: it is the producer's to reuse from now on.
        let held = consumerSlot.load(ordering: .relaxed)
        let previous = control.exchange(held, ordering: .acquiringAndReleasing)
        let slot = previous & Self.indexMask
        consumerSlot.store(slot, ordering: .relaxed)
        let source = UnsafePointer(slots + slot * count)
        out.withUnsafeMutableBufferPointer { destination in
            guard let base = destination.baseAddress else { return }
            base.update(from: source, count: min(count, destination.count))
        }
        return true
    }
}
