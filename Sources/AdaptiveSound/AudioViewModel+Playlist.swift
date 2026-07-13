import Foundation

// MARK: - AudioViewModel playlist editing

extension AudioViewModel {
    /// Reorder playlist items via drag-and-drop.
    func movePlaylistItems(from source: IndexSet, to destination: Int) {
        logUX("movePlaylistItems: \(source.map { $0 }) → \(destination)")
        // Re-anchor the current selection by the moved slot's stable UUID (dups-safe).
        let movedID = selectedTrackIndex.flatMap { current in
            source.contains(current) ? queue[current].id : nil
        }
        queue.move(fromOffsets: source, toOffset: destination)
        if let movedID {
            selectedTrackIndex = queue.firstIndex(where: { $0.id == movedID })
        }
        scheduleQueueMirror()
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
