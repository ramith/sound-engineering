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
// write at once (the didSets in AudioViewModel.swift), and so does a pause, a scrub while paused or a stop (the
// resume point). While a song plays, the playhead asks each time it has moved `playheadCadenceSeconds` (5 s)
// of the song — so a crash comes back at most 5 s early, for one row of a few dozen bytes per write. A request
// made while a write is in flight waits, and requests made meanwhile coalesce into one: the sink writes the
// queue AS IT IS when its turn comes, never a state from the middle of a verb. A request whose record has not
// changed since the last write moves the playhead alone — a number, not the queue.
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

    /// The playhead moved. A pause, a scrub while paused or a stop (`cadenced: false`) is written at once; a
    /// playing song's playhead each time it has moved `playheadCadenceSeconds`.
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
    /// playhead alone when the record is the one last written, else the whole record with its playhead. A
    /// failure is logged and leaves the stored state as it was; the next write is whole.
    func writeQueueState() async {
        guard let store = library?.store else { return }
        let revision = queueStateBook.revision
        let selected = selectedSlotID != nil
        let offset = QueueResumeRecord.storedOffset(playbackPosition, selected: selected)
        do {
            if let written = queueStateBook.written, written.revision == revision,
               try await store.saveQueuePlayhead(offset, revision: written.storeRevision) {
                return
            }
            guard let record = queueResumeRecord(offset: offset) else {
                logUX("queue state not written: the queue, the selected song and the shuffle pass disagree")
                return
            }
            let storeRevision = try await store.saveQueueState(record: record.encodedQueue(), offset: record.offset)
            queueStateBook.written = (revision, storeRevision)
        } catch {
            queueStateBook.written = nil
            logUX("queue state not written (written whole at the next change): \(error)")
        }
    }

    /// The queue as a resume record, `offset` seconds into the selected song: its slots as they persist —
    /// a library song by its id, any other file by its path (seam S5, no `tracks` row needed) — the selected
    /// one, and the shuffle pass.
    func queueResumeRecord(offset: Double) -> QueueResumeRecord? {
        QueueResumeRecord(queue: queue, id: \.id, ref: \.file.queueSlotRef, selected: selectedSlotID, offset: offset,
                          shuffle: shufflePass)
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

    /// `+Lifecycle.shutdown` cancels this before the last write: the one writer has no task of its own to
    /// cancel (it writes as asked, not after a debounce), so there is none.
    var queueMirrorTask: Task<Void, Never>? {
        nil
    }
}

extension AudioFile {
    /// How this file's queue slot persists (seam S5): a library song by its id; any other file by its path,
    /// with no `tracks` row (US-LIB-02, "no orphan row").
    var queueSlotRef: QueueSlotRef {
        trackID.map { .track(id: $0) } ?? .loose(path: absoluteURL.path)
    }

    /// A loose file's slot coming back by its path (`+QueueHydration`): named by its filename until its
    /// tags are read, its length unknown (0) until it plays.
    init(restoringLoose path: String) {
        let url = URL(fileURLWithPath: path)
        self.init(name: url.deletingPathExtension().lastPathComponent, relativePath: "", absoluteURL: url,
                  format: url.pathExtension.uppercased(), durationSeconds: 0)
    }
}
