// MARK: - PlaylistsModel + play verbs (C; split out for file length)

/// The open playlist's play verbs, delegating to `AudioViewModel`'s queue verbs. They read the
/// loaded `detail` and write nothing of the model's own, so they live in this same-type extension
/// (like `+DeadFiles`).
extension PlaylistsModel {
    /// Playable entries of the open playlist, in order — the AVAILABLE ones (track resolved AND file
    /// on disk). Unavailable (missing-file) entries are SKIPPED on play, never halting (F); the UI
    /// still shows them, badged, with Locate / Remove.
    private var resolvedEntries: [PlaylistDetailEntry] {
        detail.filter(\.isAvailable)
    }

    private func playableFiles() -> [AudioFile] {
        resolvedEntries.compactMap(\.display).map { AudioFile($0) }
    }

    /// Play the open playlist NOW — REPLACES the queue, with a one-level "Restore previous queue"
    /// undo (D-play). Starts at `entryID` (a tapped row) or the top. Returns whether it actually
    /// replaced (false if nothing is playable) so the caller only raises the undo toast on a replace.
    @discardableResult
    func playPlaylist(startingAt entryID: Int64? = nil) -> Bool {
        let entries = resolvedEntries
        let files = entries.compactMap(\.display).map { AudioFile($0) }
        guard !files.isEmpty else { return false }
        let start = entryID.flatMap { id in entries.firstIndex { $0.id == id } } ?? 0
        audio.playNowWithUndo(files, startAt: start)
        return true
    }

    /// Shuffle the open playlist (the header's Shuffle, S10.8 E4): the queue verb every page's
    /// Shuffle is (`AudioViewModel.shufflePlay`), with Play's undo — which also puts shuffle back as
    /// it was. Returns whether it replaced.
    @discardableResult
    func shufflePlaylist() -> Bool {
        let files = playableFiles()
        guard !files.isEmpty else { return false }
        audio.shufflePlay(files, undoable: true)
        return true
    }

    /// Insert the WHOLE open playlist's tracks right after the current one (header Play Next).
    /// Returns the count — 0 when nothing in it is playable.
    func playPlaylistNext() -> Int {
        let files = playableFiles()
        guard !files.isEmpty else { return 0 }
        return audio.playNext(files)
    }

    /// Insert a SINGLE entry's track right after the current one (per-row "Play Next"). Returns count.
    func playEntryNext(_ entryID: Int64) -> Int {
        guard let display = resolvedEntries.first(where: { $0.id == entryID })?.display else { return 0 }
        return audio.playNext([AudioFile(display)])
    }

    /// Append the open playlist's tracks to the end of the queue (Add to Queue). Returns the count —
    /// 0 when nothing in it is playable.
    func appendPlaylist() -> Int {
        let files = playableFiles()
        guard !files.isEmpty else { return 0 }
        return audio.appendToQueue(files)
    }

    /// Whether a "Restore previous queue" undo is available (a Play-replace happened).
    var canRestorePreviousQueue: Bool {
        audio.canRestorePreviousQueue
    }

    /// Restore the queue that a "Play" replaced (one-level undo).
    func restorePreviousQueue() {
        audio.restorePreviousQueue()
    }
}
