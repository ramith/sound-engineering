import Foundation
import LibraryBrowseKit
import LibraryStore

// MARK: - Files from outside the library: Open…, a drop on the app, Open With (R1.1-B, US-LIB-02)

/// A file outside every music folder plays without joining the library: no `tracks` row is written (a
/// playlist add is what makes one — `PlaylistsModel.add`). The opened files play NOW: the first right after
/// the song playing, the rest after it, the queue after them — the Songs list's double-click, for several
/// files (`AudioViewModel.playTrackNextNow` + `playNext`), so opening a file never throws the queue away. A
/// file the library already holds plays as that library song, so its plays count — and an open while the
/// store is still opening at launch waits for it, so that holds then too (break-it BI-P05). A queue slot of
/// a loose file is persisted by its path (`AudioFile.slotRef`, seam S5). Files of kinds the app does not
/// play, and folders, are passed over and said so (`LooseFiles`).
///
/// The disk is read off the main actor (is each one a folder? — review S2), the library in one batched read
/// (review N9), and the opens run one after another, in the order they came (`fileOpenTask`, N9).
@MainActor
extension LibraryBrowseModel {
    /// Play `urls` (see the extension's header). Waits for the store while it opens, and for the audio
    /// engine when it is not up yet (Open With launching the app).
    func openFiles(_ urls: [URL]) {
        enqueueFileOpen(urls) { [weak self] files in
            await self?.engineReady()
            self?.playOpened(files)
        }
    }

    /// Files dropped on the queue from Finder: they join its end, as Add to Queue does — confirmed by the
    /// queue toast; the kinds it can't play are passed over and said so.
    func appendFiles(_ urls: [URL]) {
        enqueueFileOpen(urls) { [weak self] files in
            guard let self else { return }
            showQueueToast(.addToQueue, added: audio.appendToQueue(files))
        }
    }

    /// Open `urls` after every open before it: read which of them play (off the main actor), say what was
    /// passed over, wait for the store if it is still opening, resolve the files to the queue's, then `act`.
    private func enqueueFileOpen(_ urls: [URL], act: @escaping @MainActor ([AudioFile]) async -> Void) {
        let previous = fileOpenTask
        fileOpenTask = Task { [weak self] in
            await previous?.value
            let opened = await LooseFiles.planned(urls)
            guard let self else { return }
            if let message = opened.skippedMessage {
                showToast(message)
            }
            guard !opened.plan.playable.isEmpty else { return }
            logUX("openFiles: \(opened.plan.playable.count) file(s), \(opened.plan.skipped.count) passed over")
            let files = await queueFiles(for: opened.plan.playable, in: library.openedStore())
            await act(files)
        }
    }

    /// The queue's files for `urls`: a library song where `store` holds the file (one batched read), else a
    /// loose file.
    func queueFiles(for urls: [URL], in store: LibraryStore?) async -> [AudioFile] {
        guard let store else { return urls.map(AudioFile.init(looseFileAt:)) }
        let songs = (try? await store.tracksDisplay(urls: urls)) ?? [:]
        return urls.map { url in songs[url].map(AudioFile.init) ?? AudioFile(looseFileAt: url) }
    }

    /// Play `files` now: the first after the song playing, the rest after it.
    private func playOpened(_ files: [AudioFile]) {
        guard let first = files.first else { return }
        audio.playTrackNextNow(first)
        if files.count > 1 {
            audio.playNext(Array(files.dropFirst()))
        }
    }

    /// Return once the audio engine is up — at once when it is.
    private func engineReady() async {
        while !audio.isEngineReady {
            await withCheckedContinuation { (ready: CheckedContinuation<Void, Never>) in
                withObservationTracking {
                    _ = audio.isEngineReady
                } onChange: {
                    ready.resume()
                }
            }
        }
    }
}
