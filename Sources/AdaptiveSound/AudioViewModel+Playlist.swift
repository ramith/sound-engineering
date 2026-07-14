import Foundation

// MARK: - AudioViewModel playlist editing

extension AudioViewModel {
    /// Reorder playlist items (drag-drop or the context-menu Move commands).
    func movePlaylistItems(from source: IndexSet, to destination: Int) {
        logUX("movePlaylistItems: \(source.map { $0 }) → \(destination)")
        // Capture the identities of the now-playing pointer AND the armed gapless on-deck BEFORE
        // the move, then re-find them by id after — so a reorder that shifts (not just moves) the
        // selected row keeps `selectedTrackIndex` on the right track, and `pendingNextIndex` keeps
        // pointing at the SAME track the engine already armed (`engine.setNextTrack`). Doing
        // neither desynced audio ⟂ the ▶/History ⟂ play-count at the gapless seam (QA: reorder a
        // playing queue → wrong next track). Dups-safe (QueueItem.id, not URL/index).
        let selID = selectedTrackIndex.flatMap { $0 < queue.count ? queue[$0].id : nil }
        let pendingID = pendingNextIndex.flatMap { $0 < queue.count ? queue[$0].id : nil }
        queue.move(fromOffsets: source, toOffset: destination)
        selectedTrackIndex = selID.flatMap { id in queue.firstIndex { $0.id == id } }
        pendingNextIndex = pendingID.flatMap { id in queue.firstIndex { $0.id == id } }
        scheduleQueueMirror()
    }

    /// Explicit single-row reorder (the context-menu / discoverable path, so reordering doesn't
    /// depend on the finicky native row-drag). Each routes through `movePlaylistItems`, so it
    /// re-anchors the current selection by `QueueItem.id` and mirrors the settled queue.
    /// `toOffset` uses SwiftUI's pre-removal `move(fromOffsets:toOffset:)` convention (move-down is
    /// `index + 2`). Boundary calls (up at 0, down at the end) are no-ops.
    func moveTrackToTop(_ index: Int) {
        reorderTrack(at: index, toOffset: 0)
    }

    func moveTrackUp(_ index: Int) {
        reorderTrack(at: index, toOffset: index - 1)
    }

    func moveTrackDown(_ index: Int) {
        reorderTrack(at: index, toOffset: index + 2)
    }

    func moveTrackToBottom(_ index: Int) {
        reorderTrack(at: index, toOffset: queue.count)
    }

    private func reorderTrack(at index: Int, toOffset destination: Int) {
        guard index >= 0, index < queue.count, destination >= 0, destination <= queue.count,
              destination != index, destination != index + 1 else { return }
        movePlaylistItems(from: IndexSet(integer: index), to: destination)
    }

    /// Drag-reorder drop handler: move the dragged row (resolved by its stable `QueueItem.id`, so a
    /// mid-drag queue shift can't mistarget it) so it lands AT the drop row `toIndex` — dragging
    /// DOWN inserts after the target, UP before it. Returns whether a move happened.
    @discardableResult
    func moveByDrop(fromID: UUID, toIndex: Int) -> Bool {
        guard let from = queue.firstIndex(where: { $0.id == fromID }),
              toIndex >= 0, toIndex < queue.count, from != toIndex else { return false }
        movePlaylistItems(from: IndexSet(integer: from), to: from < toIndex ? toIndex + 1 : toIndex)
        return true
    }

    /// Remove a track from the queue.
    func removeTrack(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        logUX("removeTrack: index=\(index) '\(queue[index].file.name)'")

        let removingCurrent = (selectedTrackIndex == index)
        queue.remove(at: index)
        scheduleQueueMirror()

        adjustPendingNextIndexAfterRemoval(removedIndex: index)

        if removingCurrent, isPlaying {
            logUX("removeTrack: removed currently-playing track, stopping")
            pendingNextIndex = nil
            stopPlayback()
            selectedTrackIndex = index < queue.count ? index : (index > 0 ? index - 1 : nil)
            return
        }

        if selectedTrackIndex == index {
            selectedTrackIndex = index < queue.count ? index : (index > 0 ? index - 1 : nil)
        } else if let cur = selectedTrackIndex, cur > index {
            selectedTrackIndex = cur - 1
        }
    }

    /// Keep `pendingNextIndex` (the on-deck track the engine has preloaded) in sync after
    /// `playlist.remove(at: removedIndex)`: re-derive it if the on-deck track itself was removed,
    /// or shift it down by one if it sat after the removed slot.
    private func adjustPendingNextIndexAfterRemoval(removedIndex: Int) {
        guard let pending = pendingNextIndex else { return }

        if pending == removedIndex {
            // The on-deck track was removed. Re-compute the next index from the current
            // playing track so the engine stays primed (rather than leaving it with nil).
            // P2-2: playlist.remove(at:) above has already shifted indices — if the
            // currently-playing track was AFTER the removed slot its index is now one lower.
            let rawCurrent = selectedTrackIndex ?? 0
            let currentIdx = rawCurrent > removedIndex ? rawCurrent - 1 : rawCurrent
            let newNextIdx = computeNextIndex(current: currentIdx, playlistCount: queue.count)
            pendingNextIndex = newNextIdx
            Task { [weak self] in
                guard let self else { return }
                if let newIdx = newNextIdx, newIdx < queue.count {
                    await engine.setNextTrack(queue[newIdx].file.absoluteURL)
                } else {
                    await engine.setNextTrack(nil)
                }
            }
        } else if pending > removedIndex {
            pendingNextIndex = pending - 1
        }
    }

    /// Clear the entire playlist. Stops playback and clears the on-deck track.
    func clearPlaylist() {
        logUX("clearPlaylist: removing \(queue.count) track(s)")
        queue.removeAll()
        scheduleQueueMirror()
        selectedTrackIndex = nil
        pendingNextIndex = nil
        stopPlayback()
    }

    /// Toggle shuffle mode.
    func toggleShuffle() {
        shuffleEnabled.toggle()
        logUX("shuffle → \(shuffleEnabled)")
    }

    /// Cycle through repeat modes: 0 (off) → 1 (all) → 2 (one) → 0
    func cycleRepeatMode() {
        repeatMode = (repeatMode + 1) % 3
        let label = ["off", "all", "one"][repeatMode]
        logUX("repeat → \(label) (\(repeatMode))")
    }
}
