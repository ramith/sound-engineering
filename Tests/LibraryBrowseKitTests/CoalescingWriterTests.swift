import LibraryBrowseKit
import Testing

// MARK: - CoalescingWriter (S10.8 E4 fix round — the playlist order writer)

/// A writer whose sink records each write and suspends like a real store write, so other work —
/// a further move, a re-read — can run while a value is being written (`duringWrite`).
@MainActor
private final class WriteLog<Value> {
    var writes: [String] = []
    var writesInFlight = 0
    var mostInFlight = 0
    /// Runs inside each write, while it is in flight.
    var duringWrite: ((String, Value) -> Void)?
    let writer: CoalescingWriter<String, Value>

    init() {
        weak var log: WriteLog?
        writer = CoalescingWriter { key, value in await log?.write(value, for: key) }
        log = self
    }

    private func write(_ value: Value, for key: String) async {
        writesInFlight += 1
        mostInFlight = max(mostInFlight, writesInFlight)
        await Task.yield()
        duringWrite?(key, value)
        await Task.yield()
        writes.append("\(key)=\(value)")
        writesInFlight -= 1
    }
}

@MainActor
@Suite("CoalescingWriter — the newest value per key, written once, in turn, and all of it at quit")
struct CoalescingWriterTests {
    @Test("a burst for one key is ONE write of its newest value; each key keeps its own newest")
    func newestValuePerKeyWins() async {
        let log = WriteLog<Int>()
        log.writer.submit(1, for: "A")
        log.writer.submit(2, for: "A")
        log.writer.submit(1, for: "B")
        log.writer.submit(3, for: "A")
        log.writer.submit(2, for: "B")
        await log.writer.flush()
        #expect(log.writes == ["A=3", "B=2"])
    }

    @Test("another key's move never drops a key's newest value (the single-slot bug)")
    func anotherKeyNeverDropsANewestValue() async {
        let log = WriteLog<Int>()
        log.duringWrite = { key, _ in
            guard key == "A", log.writes.isEmpty else { return }
            // While A's first value is being written: two more moves in A, then a move in B.
            log.writer.submit(2, for: "A")
            log.writer.submit(3, for: "A")
            log.writer.submit(1, for: "B")
        }
        log.writer.submit(1, for: "A")
        await log.writer.flush()
        #expect(log.writes == ["A=1", "A=3", "B=1"])
    }

    @Test("a key resubmitted mid-write waits behind the others — a busy key never starves them")
    func aBusyKeyNeverStarvesTheOthers() async {
        let log = WriteLog<Int>()
        log.duringWrite = { key, value in
            if key == "A", value < 4 {
                log.writer.submit(value + 1, for: "A") // a held Move key: A changes during every write
            }
        }
        log.writer.submit(1, for: "A")
        log.writer.submit(1, for: "B")
        log.writer.submit(1, for: "C")
        await log.writer.flush()
        #expect(log.writes == ["A=1", "B=1", "C=1", "A=2", "A=3", "A=4"])
    }

    @Test("one write at a time, whatever arrives during it")
    func oneWriteAtATime() async {
        let log = WriteLog<Int>()
        log.duringWrite = { key, value in
            if value < 3 {
                log.writer.submit(value + 1, for: key)
                log.writer.submit(value + 1, for: key + "'")
            }
        }
        log.writer.submit(1, for: "A")
        await log.writer.flush()
        #expect(log.mostInFlight == 1)
        // A'=2 was still waiting when A'=3 arrived, so it was never written.
        #expect(log.writes == ["A=1", "A=2", "A'=3", "A=3"])
    }

    @Test("a value is unsaved while it waits AND while it is written, then not; a newer one supersedes")
    func unsavedUntilWritten() async {
        let log = WriteLog<Int>()
        var seenDuringWrite: [Int?] = []
        log.duringWrite = { key, value in
            seenDuringWrite.append(log.writer.unsavedValue(for: key))
            if value == 1 {
                log.writer.submit(2, for: key)
                seenDuringWrite.append(log.writer.unsavedValue(for: key))
            }
        }
        #expect(log.writer.unsavedValue(for: "A") == nil)
        log.writer.submit(1, for: "A")
        #expect(log.writer.unsavedValue(for: "A") == 1)
        #expect(log.writer.unsavedValue(for: "B") == nil)
        await log.writer.flush()
        #expect(seenDuringWrite == [1, 2, 2])
        #expect(log.writer.unsavedValue(for: "A") == nil)
    }

    @Test("a re-read during the write never publishes over the order still being saved")
    func aReloadNeverPublishesOverAnUnsavedOrder() async {
        let stored = ["a", "b", "c"] // what a re-read that ran before the write committed saw
        let log = WriteLog<[String]>()
        var published: [[String]] = []
        func reload(_ rows: [String]) { // the model's publish: the unsaved order laid over the read
            published.append(ListOrder.applying(log.writer.unsavedValue(for: "P") ?? [], to: rows, id: \.self))
        }
        log.duringWrite = { _, order in
            reload(stored)
            if order == ["c", "a", "b"] {
                log.writer.submit(["c", "b", "a"], for: "P") // a further move while that write runs
                reload(stored)
            }
        }
        log.writer.submit(["c", "a", "b"], for: "P")
        reload(stored + ["d"]) // an add landed meanwhile: the new row follows the moved ones
        await log.writer.flush()
        reload(["c", "b", "a"]) // after the writes: the store's order, as read
        #expect(published == [
            ["c", "a", "b", "d"], ["c", "a", "b"], ["c", "b", "a"], ["c", "b", "a"], ["c", "b", "a"],
        ])
        #expect(log.writes == [#"P=["c", "a", "b"]"#, #"P=["c", "b", "a"]"#])
    }

    @Test("flush returns only once everything is written — including what arrives during the flush")
    func flushDrainsEverything() async {
        let log = WriteLog<Int>()
        log.duringWrite = { key, _ in
            if key == "C" {
                log.writer.submit(1, for: "D")
            }
        }
        await log.writer.flush() // idle: returns at once
        #expect(log.writes.isEmpty)
        log.writer.submit(1, for: "A")
        log.writer.submit(1, for: "B")
        log.writer.submit(1, for: "C")
        await log.writer.flush()
        #expect(log.writes == ["A=1", "B=1", "C=1", "D=1"])
        for key in ["A", "B", "C", "D"] {
            #expect(log.writer.unsavedValue(for: key) == nil)
        }
        log.writer.submit(2, for: "A") // and it starts again after a flush
        await log.writer.flush()
        #expect(log.writes.last == "A=2")
    }
}
