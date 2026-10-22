import Foundation
import PlaybackQueueKit
import RigKit
import Synchronization
import Testing

// MARK: - TransportSnapshot — the tick reads a copy, never the engine (VM-TS)

//
// The S10.8 G disconnect freeze: the main thread's transport tick asked the player node for its
// playhead while macOS held the dying device's lock, and waited seven seconds. The engine now
// samples off the main thread and publishes through `SnapshotChannel`; these tests pin the property
// that makes the tick safe — a publisher stuck in its work never makes a reader wait.

@Suite("PlaybackQueueKit — TransportSnapshot, read without waiting (VM-TS)", .timeLimit(.minutes(3)))
struct TransportSnapshotTests {
    @Test("VM-TS-01: a reader gets the last published value")
    func readsLatest() {
        let channel = SnapshotChannel(TransportSnapshot())
        #expect(channel.read() == TransportSnapshot(position: nil, transitionCount: 0, ended: false))
        channel.publish(TransportSnapshot(position: 90, transitionCount: 3, ended: false))
        #expect(channel.read().position == 90)
        #expect(channel.read().transitionCount == 3)
        channel.publish(TransportSnapshot(position: nil, transitionCount: 3, ended: true))
        #expect(channel.read().position == nil)
        #expect(channel.read().ended)
    }

    @Test("VM-TS-02: a publisher stuck mid-sample (the 7 s CoreAudio wait) never delays a reader")
    func stuckPublisherNeverBlocksReader() async throws {
        let channel = SnapshotChannel(TransportSnapshot(position: 90, transitionCount: 1, ended: false))
        let readsDone = Atomic<Int>(0)
        try await withHold("the publisher, stuck inside its sample") { stuck in
            // The engine's clock: it starts a sample, and the "player" it reads blocks until released.
            let publisher = Task {
                try await blocking("publisher") {
                    stuck.wait() // stuck inside the read, as -[AVAudioPlayerNode isPlaying] was
                    channel.publish(TransportSnapshot(position: 91, transitionCount: 1, ended: false))
                }
            }
            try await stuck.arrived()

            // 60 ticks' worth of reads (3 s at 20 Hz) while it STAYS stuck — held until the reads are done,
            // not for a while. Each must return the last value: if a read waited on the publisher it could
            // never finish (the hold ends only when this test releases it), and the wait below fails naming
            // it. No duration is measured: how long a read took is the machine's business, not the code's.
            let reader = Task {
                try await blocking("reader") {
                    for _ in 0 ..< 60 {
                        guard channel.read().position == 90 else { return false }
                        readsDone.add(1, ordering: .relaxed)
                    }
                    return true
                }
            }
            try await until("60 reads to complete while the publisher is stuck", cap: .seconds(60)) {
                readsDone.load(ordering: .relaxed) == 60
            }
            let allSawTheLastValue = try await reader.value
            #expect(allSawTheLastValue, "a read saw something but the last published value")

            stuck.release()
            try await publisher.value // the publisher finished
        }
        #expect(channel.read().position == 91)
    }

    @Test("VM-TS-03: concurrent publishers and readers never tear a snapshot")
    func noTornSnapshots() async {
        let channel = SnapshotChannel(TransportSnapshot(position: 0, transitionCount: 0, ended: false))
        // Every published snapshot satisfies position == transitionCount; a torn read would not.
        await withTaskGroup(of: Bool.self) { group in
            for writer in 0 ..< 4 {
                group.addTask {
                    for step in 0 ..< 2000 {
                        let value = UInt64(writer * 10000 + step)
                        channel.publish(TransportSnapshot(position: Double(value), transitionCount: value))
                    }
                    return true
                }
            }
            for _ in 0 ..< 4 {
                group.addTask {
                    for _ in 0 ..< 2000 {
                        let seen = channel.read()
                        if seen.position != Double(seen.transitionCount) {
                            return false
                        }
                    }
                    return true
                }
            }
            for await consistent in group {
                #expect(consistent)
            }
        }
    }

    @Test("VM-TS-04: a sample is current only once the engine has begun the latest requested operation")
    func epochGatesStaleSamples() {
        // The engine's last begun operation was #3: its samples (and a transitional one) carry epoch 3.
        let sample = TransportSnapshot(epoch: 3, position: 41, transitionCount: 2, ended: true)
        #expect(sample.isCurrent(for: 3))
        #expect(sample.isCurrent(for: 2), "a newer engine sample answers an older request too")
        // The reader asked for #4 (a start, still queued behind a slow device): #3's end flag and
        // playhead belong to the playback #4 replaces — not current.
        #expect(!sample.isCurrent(for: 4))
        #expect(TransportSnapshot().isCurrent(for: 0))
    }
}
