import AppKit
import Foundation
import MediaPlayer
import PlaybackQueueKit

// MARK: - Resolved track metadata

/// Display metadata for the current track (artist / album / artwork key), returned by the injected
/// `resolveMetadata` closure. A struct, not a tuple, so it stays under the `large_tuple` lint (same
/// reason `FrecencyState` is a struct).
struct ResolvedTrackMeta {
    let artist: String
    let album: String?
    let artworkKey: String?
}

// MARK: - NowPlayingController (S10.4)

/// Drives macOS system control: `MPNowPlayingInfoCenter` (Control Center + the menu-bar Now Playing
/// widget + lock screen) and `MPRemoteCommandCenter` (media keys + Control Center transport). A
/// read-only consumer of `AudioViewModel` + a caller of its existing transport verbs — no new
/// playback state, no engine change. Owned by the composition root; the VM's `onNowPlayingRefresh`
/// closure calls `scheduleRefresh()` (one-directional, no back-reference). Store access is via
/// injected closures so this stays store-agnostic + the pure display logic lives in
/// `PlaybackQueueKit.NowPlayingSnapshot`.
@MainActor
@Observable
final class NowPlayingController {
    /// Non-owning reference to pull snapshot state + call transport verbs from command handlers.
    weak var audio: AudioViewModel?

    /// Resolve a library track's display metadata (artist / album / artwork key) by durable id.
    /// Injected over `library.store` so the controller never imports the store. Called on the main
    /// actor (not `@Sendable`), so it may capture the main-actor peers. Nil = not resolved.
    var resolveMetadata: ((Int64) async -> ResolvedTrackMeta?)?
    /// Load a cover image by artwork cache key. Called on the main actor. Nil = no image.
    var loadArtwork: ((String) async -> NSImage?)?

    /// Cached resolved metadata + artwork, keyed by the current track token, so play/pause/seek
    /// pushes reuse them (only a track CHANGE re-resolves).
    private var metaToken: String?
    private var meta: ResolvedTrackMeta?
    private var artworkToken: String?
    private var artwork: NSImage?

    /// Coalescing guard: a burst of `didSet`s at a track start collapses into one push.
    private var refreshScheduled = false
    private var commandTokens: [(command: MPRemoteCommand, token: Any)] = []
    private var commandsRegistered = false
    /// Latched at quit (`prepareForTermination`). Blocks all further refreshes so the async engine
    /// teardown — whose `performStop()` fires `isPlaying=false` → the refresh hook — cannot re-push
    /// the track AFTER `clear()` cleared it (S10.4 QA #3 / Fool FN-2).
    private var isTerminating = false

    // MARK: UI display (D2 — footer / Now Playing widget read these)

    /// The single resolved metadata source the footer + Now Playing widget read (D2 — instead of a
    /// hardcoded "Unknown Artist"), so the id→display resolve happens ONCE here, not duplicated in
    /// the views. Both are token-guarded: they return nil unless the resolved value belongs to the
    /// track currently selected, so the async-resolve gap never flashes the previous track's
    /// metadata. nil → the view shows its own fallback. (Album goes only to Control Center via the
    /// snapshot's `albumName`; the compact in-app footer/widget show artist only.)
    var currentArtist: String? {
        liveMeta?.artist
    }

    var currentArtwork: NSImage? {
        guard let artworkToken, isStillCurrent(artworkToken) else { return nil }
        return artwork
    }

    private var liveMeta: ResolvedTrackMeta? {
        guard let metaToken, isStillCurrent(metaToken) else { return nil }
        return meta
    }

    // MARK: Command registration (once, at launch)

    /// Register the remote-command handlers ONCE. Enabling only the handled commands (leaving the
    /// rest disabled) is what marks the app a media app + keeps the media keys routed to it.
    func registerCommands() {
        guard !commandsRegistered else { return }
        commandsRegistered = true
        let center = MPRemoteCommandCenter.shared()

        add(center.togglePlayPauseCommand) { [weak self] in self?.audio?.togglePlayPause() }
        add(center.playCommand) { [weak self] in self?.audio?.play() }
        add(center.pauseCommand) { [weak self] in self?.audio?.pause() }
        add(center.nextTrackCommand) { [weak self] in self?.audio?.nextTrack() }
        add(center.previousTrackCommand) { [weak self] in self?.audio?.previousTrack() }

        center.changePlaybackPositionCommand.isEnabled = true
        let seekToken = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.audio?.seek(to: position) }
            return .success
        }
        commandTokens.append((center.changePlaybackPositionCommand, seekToken))
    }

    /// Register one no-argument command → transport verb (handlers fire off-main → hop to @MainActor).
    private func add(_ command: MPRemoteCommand, _ verb: @escaping @MainActor () -> Void) {
        command.isEnabled = true
        let token = command.addTarget { _ in
            Task { @MainActor in verb() }
            return .success
        }
        commandTokens.append((command, token))
    }

    // MARK: Refresh (coalesced, event-driven — never per-tick)

    /// Coalesce a refresh onto the next runloop turn so the `didSet` burst at a track start
    /// (selectedTrackIndex, then isPlaying) becomes ONE push carrying final state.
    func scheduleRefresh() {
        guard !refreshScheduled, !isTerminating else { return }
        refreshScheduled = true
        Task { @MainActor [weak self] in
            self?.refreshScheduled = false
            self?.refresh()
        }
    }

    private func refresh() {
        guard !isTerminating else { return }
        guard let audio, let index = audio.selectedTrackIndex, index < audio.queue.count else {
            clear() // no current track → clear Now Playing
            return
        }
        // Stopped / finished / never-started: Stop (⌘.), end-of-queue, or a fresh restored cursor
        // all leave the track SELECTED but at position 0 with no resume point. That's not an active
        // or paused-mid-track session, so clear Now Playing rather than push a phantom paused-at-0:00
        // track (design §3/§7; S10.4 FN-1). A Pause keeps `pausedResumePosition`, so it stays shown.
        if NowPlayingSnapshot.isStopped(
            isPlaying: audio.isPlaying,
            elapsedSeconds: audio.playbackPosition,
            hasResumePoint: audio.pausedResumePosition != nil
        ) {
            clear()
            return
        }
        let file = audio.queue[index].file
        let token = trackToken(file)
        // Reuse cached metadata/artwork only if it belongs to the current track.
        let resolved = (metaToken == token) ? meta : nil
        let image = (artworkToken == token) ? artwork : nil

        let snapshot = NowPlayingSnapshot(
            title: file.name,
            artistName: resolved?.artist ?? "",
            albumName: resolved?.album ?? nil,
            durationSeconds: audio.duration,
            elapsedSeconds: audio.playbackPosition,
            state: audio.isPlaying ? .playing : .paused,
            artworkKey: resolved?.artworkKey,
            trackToken: token
        )
        push(snapshot, artwork: image)
        updateCommandEnablement(audio)

        // Track changed → resolve metadata + artwork asynchronously, then re-push (stale-guarded).
        if metaToken != token, let trackID = file.trackID {
            resolveAndRepush(trackID: trackID, token: token)
        } else if file.trackID == nil, metaToken != token {
            // Loose file: title-only. Only write on an actual track change — else a same-value
            // rewrite every play/pause push thrashes the @Observable footer/widget (S10.4 QA #5).
            metaToken = token
            meta = nil
        }
    }

    /// Async-enrich the current track's metadata + artwork; apply each only if the track is still
    /// current (a fast skip past a track must not stamp its art onto the next one).
    private func resolveAndRepush(trackID: Int64, token: String) {
        Task { @MainActor [weak self] in
            guard let self, let resolved = await resolveMetadata?(trackID) else { return }
            guard isStillCurrent(token) else { return }
            metaToken = token
            meta = resolved
            refresh() // re-push with artist/album
            guard let key = resolved.artworkKey, let image = await loadArtwork?(key), isStillCurrent(token) else {
                return
            }
            artworkToken = token
            artwork = image
            refresh() // re-push with artwork
        }
    }

    // MARK: MediaPlayer push

    private func push(_ snapshot: NowPlayingSnapshot, artwork: NSImage?) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: snapshot.title,
            MPMediaItemPropertyPlaybackDuration: snapshot.durationSeconds,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.elapsedSeconds,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.rate,
        ]
        if let artist = snapshot.artist { info[MPMediaItemPropertyArtist] = artist }
        if let album = snapshot.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = playbackState(snapshot.state) // macOS: MUST be set explicitly
    }

    /// Clear Now Playing (stopped / no track). Latch-free so the stopped-state path in `refresh()`
    /// can call it repeatedly without disabling future refreshes.
    func clear() {
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
        metaToken = nil; meta = nil; artworkToken = nil; artwork = nil
    }

    /// Quit teardown: latch OFF all further refreshes, THEN clear — so the async engine shutdown
    /// (which flips `isPlaying` and fires the refresh hook) can't re-push the track after this
    /// clears it (S10.4 QA #3 / Fool FN-2). Called synchronously from `applicationShouldTerminate`.
    func prepareForTermination() {
        isTerminating = true
        clear()
    }

    private func updateCommandEnablement(_ audio: AudioViewModel) {
        let center = MPRemoteCommandCenter.shared()
        let hasTrack = audio.selectedTrackIndex != nil
        center.togglePlayPauseCommand.isEnabled = hasTrack
        center.playCommand.isEnabled = hasTrack
        center.pauseCommand.isEnabled = audio.isPlaying
        center.nextTrackCommand.isEnabled = audio.canGoNext
        center.previousTrackCommand.isEnabled = audio.canGoPrevious
        center.changePlaybackPositionCommand.isEnabled = audio.duration > 0
    }

    // MARK: Helpers

    /// Stable per-track identity: the durable id when present, else the file URL (loose files).
    private func trackToken(_ file: AudioFile) -> String {
        file.trackID.map(String.init) ?? file.absoluteURL.absoluteString
    }

    private func isStillCurrent(_ token: String) -> Bool {
        guard let audio, let index = audio.selectedTrackIndex, index < audio.queue.count else { return false }
        return trackToken(audio.queue[index].file) == token
    }

    private func playbackState(_ state: NowPlayingState) -> MPNowPlayingPlaybackState {
        switch state {
        case .playing: .playing
        case .paused: .paused
        case .stopped: .stopped
        }
    }
}
