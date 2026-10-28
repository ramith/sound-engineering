// PlaybackQueueKit — what a crash or a quit leaves to come back to: the queue's resume record (R1.1-B;
// council C-65, KI-PB-21).
//
// The queue's songs used to live in the store's built-in "current" playlist (written 250 ms after an
// edit, only library songs) and its cursor in the defaults (written only at a clean quit): two stores and
// no crash cadence, so a crash or force-quit lost the place, and a loose file was dropped. The record is
// the one value instead — the slots (`QueueSlotRef`, seam S5), the selected slot and the offset into it,
// and the shuffle pass — written by the app's one writer in one store transaction, so whatever instant
// the process dies, the store holds the previous record or the next one, never a mix.
//
// Not `QueueRestorePoint`: that is the one-level "Restore previous queue" undo, in memory only.
//
// Pure: the store keeps the encoded text and the offset as given (`LibraryStore+QueueState`); resolving a
// slot to a song (a store read, or a path) is the caller's, and what can't be resolved any more is
// dropped here, the tolerant way the cursor always was (QA break-it #2): never a wrong song or offset.
// Foundation for its JSON coder only: the stored form is JSON, so `sqlite3` and a reviewer can read it.

import Foundation

/// The queue as a crash or a quit leaves it: its slots, the selected one, how far into it, and the shuffle
/// pass.
public struct QueueResumeRecord: Equatable, Sendable {
    /// The stored form's version. A record of a higher version is not read (`DecodingError`).
    public static let format = 1

    /// How far a playing song's own progress moves the playhead before its new place is written, in seconds:
    /// the most a crash can lose. A pause, a seek (playing or paused), a stop, a song change and every edit are
    /// written at once.
    /// 5 s: a crash restarts at most one musical phrase early, for one row of a few dozen bytes per write.
    public static let playheadCadenceSeconds = 5.0

    /// The queue's slots, in its own order.
    public let slots: [QueueSlotRef]
    /// The selected slot: an index into `slots`, or nil.
    public let cursor: Int?
    /// Seconds into the selected song (0 when none is selected).
    public let offset: Double
    /// The shuffle pass, its slots indices into `slots`; nil with shuffle off.
    public let shuffle: ShufflePass<Int>?

    /// A record that holds together, or nil: `cursor` and every slot of `shuffle` index `slots`, and the
    /// pass's playing song is the selected one. The offset is a place in the selected song (negative,
    /// infinite or not a number reads as 0; with nothing selected it is 0).
    public init?(slots: [QueueSlotRef], cursor: Int?, offset: Double, shuffle: ShufflePass<Int>?) {
        let rows = slots.indices
        if let cursor, !rows.contains(cursor) {
            return nil
        }
        if let shuffle {
            let indexesSlots = (shuffle.permutation + shuffle.history).allSatisfy { rows.contains($0) }
            guard indexesSlots, shuffle.current == nil || shuffle.current == cursor else { return nil }
        }
        self.init(checked: slots, cursor: cursor, offset: offset, shuffle: shuffle)
    }

    /// The record, its parts already known to hold together.
    private init(checked slots: [QueueSlotRef], cursor: Int?, offset: Double, shuffle: ShufflePass<Int>?) {
        self.slots = slots
        self.cursor = cursor
        self.offset = Self.storedOffset(offset, selected: cursor != nil)
        self.shuffle = shuffle
    }

    /// The offset a record keeps for a playhead at `seconds`: a place in the selected song — negative,
    /// infinite or not a number reads as 0 — and 0 when no song is selected. A playhead written alone
    /// follows the same rule.
    public static func storedOffset(_ seconds: Double, selected: Bool) -> Double {
        selected && seconds.isFinite && seconds > 0 ? seconds : 0
    }

    /// The record of a live queue: `items` in order, `ref` naming what each plays, `id` its slot's identity;
    /// the slot `selected`, `offset` seconds into it; `shuffle` over the same identities. Nil if they don't
    /// hold together (a selected slot or a pass slot the queue doesn't have).
    public init?<Item, ID: Hashable & Sendable>(
        queue items: [Item], id: (Item) -> ID, ref: (Item) -> QueueSlotRef,
        selected: ID?, offset: Double, shuffle: ShufflePass<ID>?
    ) {
        var rows: [ID: Int] = [:]
        rows.reserveCapacity(items.count)
        for (row, item) in items.enumerated() {
            rows[id(item)] = row
        }
        let cursor = selected.flatMap { rows[$0] }
        if selected != nil, cursor == nil {
            return nil
        }
        var pass: ShufflePass<Int>?
        if let shuffle {
            pass = shuffle.relabeled { rows[$0] }
            if pass == nil || pass?.permutation.count != shuffle.permutation.count
                || pass?.history.count != shuffle.history.count {
                return nil
            }
        }
        self.init(slots: items.map(ref), cursor: cursor, offset: offset, shuffle: pass)
    }

    // MARK: - The stored form

    /// Everything but the offset, as the store keeps it: JSON, keys sorted, so one queue is one text. The
    /// offset is stored beside it, so a playhead move rewrites a number, not the queue.
    public func encodedQueue() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let stored = Stored(format: Self.format, slots: slots, cursor: cursor, shuffle: shuffle)
        let data = try encoder.encode(stored)
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(stored, .init(codingPath: [], debugDescription: "not UTF-8"))
        }
        return text
    }

    /// A stored record: `queue` as `encodedQueue()` wrote it, `offset` the playhead beside it. Throws on a
    /// malformed text, a newer format, or a record that does not hold together.
    public init(storedQueue queue: String, offset: Double) throws {
        let stored = try JSONDecoder().decode(Stored.self, from: Data(queue.utf8))
        guard stored.format <= Self.format else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription:
                "a queue record of format \(stored.format), newer than \(Self.format)"))
        }
        guard let record = QueueResumeRecord(slots: stored.slots, cursor: stored.cursor, offset: offset,
                                             shuffle: stored.shuffle) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription:
                "a queue record that does not hold together"))
        }
        self = record
    }

    /// The JSON shape: its field names are part of the persisted queue state — never rename one.
    private struct Stored: Codable {
        let format: Int
        let slots: [QueueSlotRef]
        let cursor: Int?
        let shuffle: ShufflePass<Int>?
    }

    // MARK: - Before the record (R1.1-A and earlier)

    /// The queue a build before the record left: the "current" playlist's songs, in order, and the cursor
    /// it kept in the defaults — a row and the song id in it — with the offset. The cursor is found the
    /// tolerant way it always was (QA break-it #2): the row when it still holds that song, else that song's
    /// first row, else none. A cursor saved before the id was (no id) takes the row as it is.
    public static func legacy(trackIDs: [Int64], cursorRow: Int?, cursorTrackID: Int64?,
                              offset: Double) -> QueueResumeRecord {
        let slots = trackIDs.map { QueueSlotRef.track(id: $0) }
        var cursor: Int?
        if let row = cursorRow, trackIDs.indices.contains(row), cursorTrackID.map({ trackIDs[row] == $0 }) ?? true {
            cursor = row
        } else if let cursorTrackID {
            cursor = trackIDs.firstIndex(of: cursorTrackID)
        }
        return QueueResumeRecord(checked: slots, cursor: cursor, offset: offset, shuffle: nil)
    }

    // MARK: - Coming back

    /// What the record resolves to once each slot is found again.
    public struct Resolved<Item> {
        /// The songs found, in the queue's order.
        public let items: [Item]
        /// The selected row in `items`, or nil.
        public let cursor: Int?
        /// Seconds into the selected song: the record's, when the selected song came back; else 0.
        public let offset: Double
        /// The shuffle pass over rows of `items`, or nil.
        public let shuffle: ShufflePass<Int>?
    }

    /// The record with each slot found again by `resolve` — a library song by its id, a loose file by its
    /// path — and every slot it can't find dropped, as a removal would: the cursor and the pass follow their
    /// songs. When the selected song itself is gone, the pass's next song is selected from its start (the
    /// shuffle goes on where it was); without a pass, nothing is (the queue starts at the top) — never
    /// another song at the old offset.
    public func resolved<Item>(_ resolve: (QueueSlotRef) -> Item?) -> Resolved<Item> {
        var items: [Item] = []
        var rows: [Int?] = []
        items.reserveCapacity(slots.count)
        rows.reserveCapacity(slots.count)
        for slot in slots {
            if let item = resolve(slot) {
                rows.append(items.count)
                items.append(item)
            } else {
                rows.append(nil)
            }
        }
        var pass = shuffle?.relabeled { rows[$0] }
        if let cursor {
            if let row = rows[cursor] {
                return Resolved(items: items, cursor: row, offset: offset, shuffle: pass)
            }
            // The selected song is gone: the pass stands just after the song before it (a removal), so its
            // next song is the one the shuffle would have played — selected, from its start.
            if let next = pass?.peekNext(repeatMode: 0) {
                pass?.arrive(at: next)
                return Resolved(items: items, cursor: next, offset: 0, shuffle: pass)
            }
        }
        return Resolved(items: items, cursor: nil, offset: 0, shuffle: nil)
    }
}
