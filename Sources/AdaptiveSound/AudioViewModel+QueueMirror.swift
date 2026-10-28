import Foundation
import LibraryBrowseKit
import LibraryStore
import PlaybackQueueKit

// MARK: - AudioViewModel: the queue's resume record and its one writer (R1.1-B; council C-65, KI-PB-21)

//
// The queue — its slots, the selected one, the shuffle pass — and the playhead are kept in the store as one
// `QueueResumeRecord` (PlaybackQueueKit), written by ONE writer: `queueStateWriter`, a `CoalescingWriter`
// (LibraryBrowseKit) whose sink, `writeQueueState`, is the only code that writes the queue state — each write
// one store transaction (`LibraryStore+QueueState`). So a crash or a force-quit at any instant leaves the
// previous state or the next one, never a mix. It replaces two stores written at different times: the
// "current" playlist (250 ms after an edit, library songs only) and a cursor in the defaults (only at a clean
// quit), which a crash could leave from two moments, or lose the place altogether.
//
// When it writes (the cadence): every change to the queue, the selected song or the shuffle pass asks for a
// write at once (the didSets in AudioViewModel.swift), and so does a pause or a stop (the resume point) and a
// scrub, playing or paused (`seek`): a place the listener chose (founder, 2026-10-28). While a song plays on, its
// own progress asks each time it has moved `playheadCadenceSeconds` (5 s) of the song — so a crash comes back
// where the listener last scrubbed to, or at most 5 s early, for one row of a few dozen bytes per write. A request
// made while a write is in flight waits, and requests made meanwhile coalesce into one: the sink writes the
// queue AS IT IS when its turn comes, never a state from the middle of a verb. A request whose record has not
// changed since the last write moves the playhead alone — a number, not the queue — and builds no record: a
// 20,000-song queue's record is not rebuilt on the main actor at every scrub or every 5 s (review S5).
//
// Nothing is written until the launch's restore has read what is stored (`+QueueHydration`), so the empty queue
// of a launch never overwrites the stored one; and nothing after the quit's last write (`mirrorQueueNow`), so the
// stop that follows it never writes the playhead back to 0.

/// The one key of the queue's writer: there is one queue.
enum QueueStateKey: Hashable {
    case current
}

/// What the queue's writer has written, and whether it may write (`AudioViewModel.queueStateBook`).
struct QueueStateBook {
    /// Bumped by every change to what the record holds: the queue, the selected song, the shuffle pass.
    var revision = 0
    /// The record last written in this launch — the `revision` it held — and the store's revision for it.
    /// Nil before the first write and after a failed one: the next write is whole.
    var written: (revision: Int, storeRevision: Int64)?
    /// The launch's restore has read what is stored: writes may begin.
    var restored = false
    /// The quit's last write is done: no write after it.
    var closed = false
    /// Where the playhead was when it last asked for a write.
    var playheadAsked = 0.0
    /// How many whole records `queueStateNow` has built: a write of the playhead alone builds none (review S5).
    var recordsBuilt = 0

    /// Whether a write may be asked for now.
    var isOpen: Bool {
        restored && !closed
    }
}

@MainActor
extension AudioViewModel {
    /// The queue, the selected song or the shuffle pass changed: the record has a new revision, written at
    /// once.
    func queueStateChanged() {
        queueStateBook.revision &+= 1
        askForQueueStateWrite()
    }

    /// The playhead moved. A pause, a stop or a scrub — playing or paused (`cadenced: false`) — is written at once;
    /// a playing song's own progress each time it has moved `playheadCadenceSeconds`.
    func queuePlayheadMoved(cadenced: Bool) {
        // A playhead back at 0 is a stop or a new song: written at once, so a stop never resumes mid-song.
        let moved = abs(playbackPosition - queueStateBook.playheadAsked)
        guard !cadenced || moved >= QueueResumeRecord.playheadCadenceSeconds || playbackPosition == 0
        else { return }
        askForQueueStateWrite()
    }

    /// Ask the one writer for a write of the queue as it will be when the write's turn comes.
    private func askForQueueStateWrite() {
        guard queueStateBook.isOpen else { return }
        queueStateBook.playheadAsked = playbackPosition
        queueStateWriter.submit((), for: .current)
    }

    /// The writer's sink — the ONLY code that writes the queue state. Writes the queue as it is now: the
    /// playhead alone when the record is the one last written — no record built — else the whole record with
    /// its playhead, built only then. A failure is logged and leaves the stored state as it was; the next
    /// write is whole.
    func writeQueueState() async {
        guard let store = library?.store else { return }
        do {
            if let written = queueStateBook.written, written.revision == queueStateBook.revision,
               try await store.saveQueuePlayhead(queueOffsetNow(), revision: written.storeRevision) {
                return
            }
            // The whole record, as it is now: the playhead's write (or its refusal) may have let it move on.
            let revision = queueStateBook.revision
            let (record, offset) = queueStateNow()
            guard let record else {
                logUX("queue state not written: the queue, the selected song and the shuffle pass disagree")
                return
            }
            let storeRevision = try await store.saveQueueState(record: Self.encoded(record), offset: offset)
            queueStateBook.written = (revision, storeRevision)
        } catch {
            queueStateBook.written = nil
            logUX("queue state not written (written whole at the next change): \(error)")
        }
    }

    /// The record's text, encoded off the main actor: a whole-library queue is half a megabyte of JSON
    /// (20,000 songs: ~26 ms in a debug build), which the main thread would otherwise spend at every song change.
    @concurrent
    private nonisolated static func encoded(_ record: QueueResumeRecord) async throws -> String {
        try record.encodedQueue()
    }

    /// The queue as its resume record holds it now — its slots as they persist (a library song by its id,
    /// any other file by its path: seam S5, no `tracks` row needed), the selected one and the shuffle pass
    /// (nil if they disagree) — and the playhead the record keeps beside it.
    func queueStateNow() -> (record: QueueResumeRecord?, offset: Double) {
        let offset = queueOffsetNow()
        queueStateBook.recordsBuilt += 1
        let record = QueueResumeRecord(queue: queue, id: \.id, ref: \.file.slotRef, selected: selectedSlotID,
                                       offset: offset, shuffle: shufflePass)
        return (record, offset)
    }

    /// The playhead the record keeps beside it now: a place in the selected song, 0 when none is selected.
    private func queueOffsetNow() -> Double {
        QueueResumeRecord.storedOffset(playbackPosition, selected: selectedSlotID != nil)
    }

    // MARK: - The quit (`+Lifecycle.shutdown`)

    /// The quit's playhead: ask for a write of the queue as it is now, before the stop zeroes the playhead.
    func persistQueueCursor() {
        askForQueueStateWrite()
    }

    /// The quit's last write: wait until everything asked for is written, then write no more — the stop that
    /// follows must not write the playhead back to 0.
    func mirrorQueueNow() async {
        await queueStateWriter.flush()
        queueStateBook.closed = true
    }
}
