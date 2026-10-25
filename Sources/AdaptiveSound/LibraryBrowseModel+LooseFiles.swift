import Foundation
import LibraryBrowseKit
import LibraryStore

// MARK: - Files from outside the library: Open…, a drop on the app, Open With (R1.1-B, US-LIB-02)

/// A file outside every music folder plays without joining the library: no `tracks` row is written (a
/// playlist add is what makes one — `PlaylistsModel.add`). The opened files play NOW: the first right after
/// the song playing, the rest after it, the queue after them — the Songs list's double-click, for several
/// files (`AudioViewModel.playTrackNextNow` + `playNext`), so opening a file never throws the queue away. A
/// file the library already holds plays as that library song, so its plays count. A queue slot of a loose
/// file is persisted by its path (`AudioFile.slotRef`, seam S5). Files of kinds the app does not play, and
/// folders, are passed over and said so (`LooseFiles`).
@MainActor
extension LibraryBrowseModel {
    /// Play `urls` (see the extension's header). Waits for the audio engine when it is not up yet (Open
    /// With launching the app).
    func openFiles(_ urls: [URL]) {
        let plan = LooseFiles.plan(urls)
        if let message = LooseFiles.skippedMessage(plan.skipped) {
            showToast(message)
        }
        guard !plan.playable.isEmpty else { return }
        logUX("openFiles: \(plan.playable.count) file(s), \(plan.skipped.count) passed over")
        Task { [weak self] in
            guard let files = await self?.queueFiles(for: plan.playable) else { return }
            self?.whenEngineReady { [weak self] in self?.playOpened(files) }
        }
    }

    /// Files dropped on the queue from Finder: they join its end, as Add to Queue does — confirmed by the
    /// queue toast; the kinds it can't play are passed over and said so.
    func appendFiles(_ urls: [URL]) {
        let plan = LooseFiles.plan(urls)
        if let message = LooseFiles.skippedMessage(plan.skipped) {
            showToast(message)
        }
        guard !plan.playable.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            let files = await queueFiles(for: plan.playable)
            showQueueToast(.addToQueue, added: audio.appendToQueue(files))
        }
    }

    /// The queue's files for `urls`: a library song where the library holds the file, else a loose file.
    func queueFiles(for urls: [URL]) async -> [AudioFile] {
        guard let store else { return urls.map(AudioFile.init(looseFileAt:)) }
        var ids: [URL: Int64] = [:]
        for url in urls {
            if let id = try? await store.track(url: url)?.id {
                ids[url] = id
            }
        }
        let songs = (try? await store.tracksDisplay(ids: Array(ids.values))) ?? [:]
        return urls.map { url in ids[url].flatMap { songs[$0] }.map(AudioFile.init) ?? AudioFile(looseFileAt: url) }
    }

    /// Play `files` now: the first after the song playing, the rest after it.
    private func playOpened(_ files: [AudioFile]) {
        guard let first = files.first else { return }
        audio.playTrackNextNow(first)
        if files.count > 1 {
            audio.playNext(Array(files.dropFirst()))
        }
    }

    /// Run `action` once the audio engine is up — at once when it is.
    private func whenEngineReady(_ action: @escaping @MainActor () -> Void) {
        guard !audio.isEngineReady else {
            action()
            return
        }
        withObservationTracking {
            _ = audio.isEngineReady
        } onChange: { [weak self] in
            Task { @MainActor in self?.whenEngineReady(action) }
        }
    }
}
