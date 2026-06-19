import Foundation

// MARK: - AudioViewModel playlist editing

extension AudioViewModel {
    /// Reorder playlist items via drag-and-drop.
    func movePlaylistItems(from source: IndexSet, to destination: Int) {
        logUX("movePlaylistItems: \(source.map { $0 }) → \(destination)")
        let movedID = selectedTrackIndex.flatMap { current in
            source.contains(current) ? playlist[current].id : nil
        }
        playlist.move(fromOffsets: source, toOffset: destination)
        if let movedID {
            selectedTrackIndex = playlist.firstIndex(where: { $0.id == movedID })
        }
    }

    /// Remove a track from the playlist.
    func removeTrack(at index: Int) {
        guard index >= 0, index < playlist.count else { return }
        logUX("removeTrack: index=\(index) '\(playlist[index].name)'")

        let removingCurrent = (selectedTrackIndex == index)
        playlist.remove(at: index)

        if let pending = pendingNextIndex {
            if pending == index {
                // The on-deck track was removed. Re-compute the next index from the current
                // playing track so the engine stays primed (rather than leaving it with nil).
                // P2-2: playlist.remove(at:) above has already shifted indices — if the
                // currently-playing track was AFTER the removed slot its index is now one lower.
                let rawCurrent = selectedTrackIndex ?? 0
                let currentIdx = rawCurrent > index ? rawCurrent - 1 : rawCurrent
                let newNextIdx = computeNextIndex(current: currentIdx, playlistCount: playlist.count)
                pendingNextIndex = newNextIdx
                Task { [weak self] in
                    guard let self else { return }
                    if let newIdx = newNextIdx, newIdx < playlist.count {
                        await engine.setNextTrack(playlist[newIdx].absoluteURL)
                    } else {
                        await engine.setNextTrack(nil)
                    }
                }
            } else if pending > index {
                pendingNextIndex = pending - 1
            }
        }

        if removingCurrent, isPlaying {
            logUX("removeTrack: removed currently-playing track, stopping")
            pendingNextIndex = nil
            stopPlayback()
            selectedTrackIndex = index < playlist.count ? index : (index > 0 ? index - 1 : nil)
            return
        }

        if selectedTrackIndex == index {
            selectedTrackIndex = index < playlist.count ? index : (index > 0 ? index - 1 : nil)
        } else if let cur = selectedTrackIndex, cur > index {
            selectedTrackIndex = cur - 1
        }
    }

    /// Clear the entire playlist. Stops playback and clears the on-deck track.
    func clearPlaylist() {
        logUX("clearPlaylist: removing \(playlist.count) track(s)")
        playlist.removeAll()
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
