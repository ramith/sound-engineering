@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineBridge Enhanced-path gapless seam handlers

/// The two seam handlers (`rollResamplerToNext` / `rollPassthroughToNext`) and their shared
/// sub-steps, split out of `AudioEngineBridge+Gapless.swift` to keep that file under the
/// file-length limit and to keep each handler under the body-length / cyclomatic-complexity
/// limits — and the same-format resampled seam, which needs no roll: the next track continues the
/// stream through the same converter (`continueStreamIntoNextTrack`, `commitJoin`).
///
/// ## Thread model (unchanged)
///
/// Everything here runs on `resampleQueue` (the serial queue that owns all resampler/converter
/// state and all gapless seam state — `onDeckURL`, `gaplessTransitionCount`,
/// `gaplessPlaybackEnded`, the EOF hooks). The handlers are invoked from the EOF hooks installed
/// by `armResamplerNextTrack` / `armPassthroughNextTrack`, both of which dispatch onto
/// `resampleQueue`. The `primeEnhancedResamplerLocked` deadlock-guard is preserved: it is called
/// DIRECTLY here (never through a `resampleQueue.sync`, which would trap on ourselves → C-1).
extension AudioEngineBridge {
    // MARK: - The same-format resampled seam: one stream (council C-22, P3 D39–D40; KI-GAP-04)

    /// Track A's input has run out — its reader delivered its last frame, at its length or, on a decoder that
    /// reads short, before it (LOW-6) — and the reader is about to read past its end, into the empty `chunk`: if
    /// the next track is armed and has A's format (rate, channel count, layout), its first frames fill the chunk
    /// and the SAME conversion goes on — the two tracks convert as one input would, with no click and no frame lost
    /// or added. The seam is counted later, when the player reaches it (`commitJoin`).
    ///
    /// When: at the read after A's last, the latest moment that keeps the join seamless — the player
    /// still holds A's last full chunk and its last partial one (186–372 ms at 44.1 kHz) — so a
    /// change of the next track up to then still counts, and the next file opens, reads and
    /// converts with a whole chunk of lead. (A roll at A's end-of-file had only A's last partial
    /// chunk and the converter's flush: the race that left 279 frames of silence, P3 D39 b.)
    ///
    /// Leaves everything as it was — A ends, and its end-of-file roll takes the next track with a
    /// fresh converter (`rollResamplerToNext`) — when nothing is armed, its format differs
    /// (remembered, so it isn't opened twice for a join), or a join is already pending. A next file
    /// that won't open or can't be decoded is refused (`refuseOnDeck`): A ends as a last song does.
    /// MUST be called on `resampleQueue`.
    func continueStreamIntoNextTrack(session: EnhancedResampleSession, filling chunk: AVAudioPCMBuffer) {
        guard chunk.frameLength == 0, session.pendingJoin == nil, onResamplerEOF != nil,
              let nextURL = onDeckURL, nextURL != session.refusedJoin else { return }
        guard let nextFile = openOnDeckFile(nextURL) else {
            refuseOnDeck(nextURL)
            return
        }
        guard session.resampler.canContinue(with: nextFile.processingFormat) else {
            session.refusedJoin = nextURL
            return
        }
        guard let next = try? TrackFileReader(reading: nextFile),
              (try? next.read(into: chunk, frameCount: chunk.frameCapacity)) != nil, chunk.frameLength > 0 else {
            chunk.frameLength = 0
            refuseOnDeck(nextURL)
            return
        }
        // Taken, as a roll takes it: the slot and its one-shot hook.
        onDeckURL = nil
        onResamplerEOF = nil
        session.continueStream(into: next, url: nextURL)
        logUX("gapless: '\(nextURL.lastPathComponent)' continues the stream "
            + "(one converter, \(Int(nextFile.processingFormat.sampleRate)) Hz)")
    }

    /// The player has consumed the last frame before the pending join (the completion of the
    /// buffer that ends there): the next track is audible now. Count the seam — the title, its
    /// loudness gain — and move the playhead base back by the ending track's length, exactly: the
    /// playhead reads the next track's own time from its first frame, however late this runs.
    /// Abandons when a seek, stop or track change superseded the session. MUST be called on
    /// `resampleQueue`.
    func commitJoin(session: EnhancedResampleSession, player: AVAudioPlayerNode, generation: UInt64) {
        guard isCurrent(generation: generation, session: session), let join = session.takePendingJoin() else {
            return
        }
        setLastFileURL(join.url)
        bumpTransitionCount(player: player, nextURL: join.url, endingTrackSeconds: join.endingTrackSeconds)
        logUX("gapless: one-stream seam '\(join.url.lastPathComponent)' reached at output frame "
            + "\(join.outputFrame)")
    }

    /// The player has consumed the session's output up to `outputFrame` (a buffer's `.dataConsumed`): a
    /// pending join at or before it has been reached — count it (`commitJoin`). This is how a join with no
    /// conversion (`StraightThrough`), which falls exactly between two chunks, is counted on the ending
    /// track's last frame. MUST be called on `resampleQueue`.
    func commitJoin(reachedBy outputFrame: Int64, session: EnhancedResampleSession, player: AVAudioPlayerNode,
                    generation: UInt64) {
        guard let join = session.pendingJoin, join.outputFrame <= outputFrame else { return }
        commitJoin(session: session, player: player, generation: generation)
    }

    /// The stream's last buffer has been heard (its `playedBackCallbackType` completion): its last
    /// track has truly ended — nothing of it is left for the view model's stop at the end of the
    /// queue to cut (S-1). A join still pending is counted first, so the seam always comes before
    /// the end. Then the end-of-track path (`fireResamplerEOFOrEnd`): a next track armed this late
    /// rolls in now, after a short gap; with none, the end flag goes up — as it does when that roll
    /// refused its next file (the session is still current: nothing replaced it). Abandons when a
    /// seek, stop or track change superseded the session (`player.stop()` fires this completion too).
    /// MUST be called on `resampleQueue`.
    func streamPlayedOut(session: EnhancedResampleSession, player: AVAudioPlayerNode, generation: UInt64) {
        guard isCurrent(generation: generation, session: session) else { return }
        if session.pendingJoin != nil {
            commitJoin(session: session, player: player, generation: generation)
        }
        fireResamplerEOFOrEnd(session: session, player: player)
        if isCurrent(generation: generation, session: session), !gaplessPlaybackEnded {
            markGaplessPlaybackEnded(reason: "resampler EOF — the next track was refused, playback ended")
        }
    }

    // MARK: - Seam handlers (called on resampleQueue)

    /// Gapless roll for the resampler sub-path, at a seam the stream could not continue through
    /// (another rate or channel count, or a next track armed too late to join the stream).
    ///
    /// Called on `resampleQueue` after the current resampler session reaches EOF (its final buffer
    /// has been consumed by the player's buffer queue). Opens the next file, creates a NEW
    /// resampler session for it, and continues the resampler chain WITHOUT stopping the player.
    /// Because the player's queue already contains A's audio tail and we are scheduling B's first
    /// buffers right behind it — with the player still running — the hardware clock is continuous
    /// and no silence is inserted.
    ///
    /// A next track that won't open or can't be decoded is refused (`openOnDeckFile`): nothing is
    /// scheduled from it, and this stream ends as a last song does — its end flag at its last
    /// buffer's played-back completion (`streamPlayedOut`), so the song before it plays to its end.
    func rollResamplerToNext(player: AVAudioPlayerNode) {
        guard let nextURL = consumeOnDeckURL(context: "resampler") else { return }

        guard let nextFile = openOnDeckFile(nextURL) else { return }

        let graphRate = player.outputFormat(forBus: 0).sampleRate
        let nextRate = nextFile.processingFormat.sampleRate

        if Self.playsStraightThrough(nextFile, graphRate: graphRate) {
            // Next file plays straight through (48 kHz, its length exact) — switch to the passthrough path for it.
            // Bump the generation so the old session's completions abandon; we don't call
            // player.stop() so the queue stays running. We are ALREADY on resampleQueue here, so
            // call the *Locked variant directly — stopEnhancedResampler() would resampleQueue.sync
            // onto ourselves and trap libdispatch (C-1 re-entrancy).
            stopEnhancedResamplerLocked()
            bumpTransitionCount(player: player, nextURL: nextURL)
            setLastFileURL(nextURL)
            scheduleFileChainingPassthrough(nextFile, player: player)
            // Arm the passthrough hook so the track after this one can also be gapless.
            armPassthroughNextTrack(player: player)
            logUX("gapless: resampler→passthrough seam '\(nextURL.lastPathComponent)'")
            return
        }

        // Next file goes through the reader too (another rate, or a decoder that may read short): continue the chain.
        setLastFileURL(nextURL)
        startResamplerChainOrFallback(
            nextFile: nextFile, player: player, nextURL: nextURL,
            nextRate: nextRate, graphRate: graphRate
        )
    }

    /// Gapless roll for the 48 kHz passthrough sub-path.
    ///
    /// Called on `resampleQueue` after the current `scheduleFile` session's `.dataPlayedBack`
    /// callback fires (the hardware has played the last sample of the current track). Opens the
    /// next file and either chains another `scheduleFile` (a next that plays straight through) or
    /// starts the reader (another rate, or a decoder that may read short) — in both cases WITHOUT
    /// calling `player.stop()`. A next that won't open or can't be decoded is refused: the current
    /// track has been heard to its end, so the end flag goes up now.
    func rollPassthroughToNext(player: AVAudioPlayerNode) {
        guard let nextURL = consumeOnDeckURL(context: "passthrough") else { return }

        guard let nextFile = openOnDeckFile(nextURL) else {
            markGaplessPlaybackEnded(reason: "passthrough EOF — the next track was refused, playback ended")
            return
        }

        let graphRate = player.outputFormat(forBus: 0).sampleRate
        let nextRate = nextFile.processingFormat.sampleRate
        setLastFileURL(nextURL)

        if Self.playsStraightThrough(nextFile, graphRate: graphRate) {
            // Both current and next are 48 kHz: consecutive scheduleFile calls play back-to-back,
            // byte-exact. This is the spec's "consecutive scheduleFile" gapless path.
            bumpTransitionCount(player: player, nextURL: nextURL)
            scheduleFileChainingPassthrough(nextFile, player: player)
            armPassthroughNextTrack(player: player)
            logUX("gapless: passthrough→passthrough seam '\(nextURL.lastPathComponent)'")
            return
        }

        // Next track goes through the reader: start the resampler sub-path for it.
        startResamplerChainOrFallback(
            nextFile: nextFile, player: player, nextURL: nextURL,
            nextRate: nextRate, graphRate: graphRate
        )
    }

    // MARK: - Shared seam sub-steps (called on resampleQueue)

    /// Consume `onDeckURL` for a seam. Returns the armed URL, or `nil` if the queue is exhausted —
    /// in which case it marks the seam ended (sets `gaplessPlaybackEnded`, clears the auto-resume
    /// intent), exactly as the inline EOF guards did. MUST be called on `resampleQueue`.
    private func consumeOnDeckURL(context: String) -> URL? {
        guard let nextURL = onDeckURL else {
            markGaplessPlaybackEnded(reason: "\(context) EOF — no next track, playback ended")
            return nil
        }
        onDeckURL = nil // consume the armed URL
        return nextURL
    }

    /// Fire the passthrough EOF hook — or, when NO hook is armed under a LIVE epoch, surface
    /// the ended state (break-it BLOCKER-1): `setNextTrack(nil)` clears the hook at the FINAL
    /// seam and a single-track queue never arms one, so the last real EOF used to be
    /// swallowed — `isPlaying` stayed true and the VM polled a silent engine forever (the
    /// footer counted past the duration). A live-epoch completion with a nil hook is provably
    /// a genuine EOF: every non-EOF stop (pause/stop/seek/track-change/Pure entry/device
    /// loss/re-establish) bumps the epoch BEFORE its `player.stop()`. MUST be called on
    /// `resampleQueue` with the epoch already validated by the caller.
    func firePassthroughEOFOrEnd(player: AVAudioPlayerNode) {
        if let hook = onPassthroughEOF {
            hook(player)
        } else {
            markGaplessPlaybackEnded(reason: "passthrough EOF — no seam armed, playback ended")
        }
    }

    /// The resampler twin: a `reachedEnd` session under a CURRENT generation with no
    /// `onResamplerEOF` armed is the same genuine end. MUST be called on `resampleQueue`.
    func fireResamplerEOFOrEnd(session: EnhancedResampleSession, player: AVAudioPlayerNode) {
        if let hook = onResamplerEOF {
            hook(session, player)
        } else {
            markGaplessPlaybackEnded(reason: "resampler EOF — no seam armed, playback ended")
        }
    }

    /// The ONE ended-state surface (the channel `AudioViewModel.tickTransport` polls):
    /// pioneered by `consumeOnDeckURL`'s empty branch, shared by the nil-hook EOF paths and the
    /// Enhanced restart's "at or past the end" (`endEnhancedTrackNow`).
    func markGaplessPlaybackEnded(reason: String) {
        gaplessPlaybackEnded = true
        enhancedPlayIntent = false // ended — don't auto-resume on a later config change
        logUX("gapless: \(reason)")
    }

    /// Open the on-deck `nextURL` for a seam (`openForPlayback`: Apple's decoder reads its first frames before
    /// anything is scheduled from it), under its security scope, which it then releases (`AVAudioFile` keeps
    /// its own handle). `nil` when it won't open or can't be decoded — the tiny-block FLAC (KI-PB-22): the seam
    /// refuses it, the song before it ends as a last song does, and the view model starts it fresh, where the
    /// refusal says why. (A clean restart here through `playFile`, on a global queue, used to try it again: the
    /// same open, refused the same way, off the bridge's queues.) MUST be called on `resampleQueue`.
    private func openOnDeckFile(_ nextURL: URL) -> AVAudioFile? {
        let didAccess = nextURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                nextURL.stopAccessingSecurityScopedResource()
            }
        }
        do {
            return try Self.openForPlayback(nextURL)
        } catch {
            logUX("gapless: '\(nextURL.lastPathComponent)' refused at the seam — \(error.localizedDescription)")
            return nil
        }
    }

    /// The on-deck `nextURL` can't play: take it off deck with its one-shot resampler hook, so the stream ends as
    /// a last song does (`streamPlayedOut` raises the end flag once its last buffer has been heard). MUST be
    /// called on `resampleQueue`.
    private func refuseOnDeck(_ nextURL: URL) {
        guard onDeckURL == nextURL else { return }
        onDeckURL = nil
        onResamplerEOF = nil
        logUX("gapless: '\(nextURL.lastPathComponent)' taken off deck — the stream ends as the last song")
    }

    /// Schedule `file` — whole: the bridge never reads an `AVAudioFile` it hands the player, nor asks or sets its
    /// place (KI-PB-22), so it is at its top — on the still-running player with a completion — once it has been
    /// heard (`playedBackCallbackType`) — that re-dispatches onto `resampleQueue` to fire `onPassthroughEOF`: the
    /// shared "consecutive scheduleFile" gapless primitive used by every passthrough seam (and the
    /// resampler→passthrough fallbacks). MUST be called on `resampleQueue`.
    private func scheduleFileChainingPassthrough(_ file: AVAudioFile, player: AVAudioPlayerNode) {
        dispatchPrecondition(condition: .onQueue(resampleQueue))
        // Under the CURRENT passthrough epoch (we're on resampleQueue, the owner; no bump — a
        // seam schedule replaces one whose completion already fired legitimately). A later
        // stop/seek/reschedule bumps the epoch, and this completion then abandons at fire time
        // instead of rolling the seam off a non-EOF `player.stop()` (wrong-song bug).
        player.scheduleFile(
            file, at: nil, completionCallbackType: player.playedBackCallbackType,
            completionHandler: observed(
                frames: file.length,
                passthroughEndOfTrack(epoch: passthroughGeneration, player: player)
            )
        )
    }

    /// Continue (or start) the resampler chain for a rate-mismatched `nextFile`: build a fresh
    /// session (its own Mastering converter) and prime it via `primeEnhancedResamplerLocked` (called
    /// DIRECTLY — we are on resampleQueue; a sync onto it would trap, C-1). On any failure path
    /// (converter creation fails, or the prime schedules nothing for an empty file) it falls back
    /// to `scheduleFileChainingPassthrough` so the seam chain is preserved (S-1). MUST be called
    /// on `resampleQueue`.
    private func startResamplerChainOrFallback(
        nextFile: AVAudioFile,
        player: AVAudioPlayerNode,
        nextURL: URL,
        nextRate: Double,
        graphRate: Double
    ) {
        guard let nextSession = EnhancedResampleSession(file: nextFile, outputFormat: player.outputFormat(forBus: 0))
        else {
            // Converter creation failed: fall back to scheduleFile (brief gap, chain preserved).
            // Clear the OLD track's exhausted session first (the P1-2 rule, same as the
            // empty-prime branch below): a stale session would make the next on-deck arm
            // (`armEnhancedOnDeck`) install the resampler's EOF hook on what is now a passthrough
            // schedule, so the next seam would never roll.
            resampleSession = nil
            // S-1: the .dataPlayedBack completion keeps onPassthroughEOF firing for the next seam.
            bumpTransitionCount(player: player, nextURL: nextURL)
            armPassthroughNextTrack(player: player)
            scheduleFileChainingPassthrough(nextFile, player: player)
            logUX("gapless: →passthrough fallback seam "
                + "'\(nextURL.lastPathComponent)' (converter failed)")
            return
        }

        let primed = primeEnhancedResamplerLocked(session: nextSession, player: player, startFrame: 0)
        if primed > 0 {
            bumpTransitionCount(player: player, nextURL: nextURL)
            armResamplerNextTrack(player: player)
            logUX("gapless: →resampler seam '\(nextURL.lastPathComponent)' "
                + "(\(Int(nextRate))→\(Int(graphRate))\(nextRate == graphRate ? ", straight through" : ""))")
            return
        }

        // primeEnhancedResamplerLocked scheduled nothing (empty file). Fall back to scheduleFile.
        // P1-2: clear resampleSession so the next on-deck arm installs the passthrough hook, not
        // the (now-stale) resampler one. primeEnhancedResamplerLocked sets it non-nil at the top of
        // its prime even when 0 buffers are produced.
        resampleSession = nil
        // S-1: completion preserves the chain.
        bumpTransitionCount(player: player, nextURL: nextURL)
        armPassthroughNextTrack(player: player)
        scheduleFileChainingPassthrough(nextFile, player: player)
        logUX("gapless: →passthrough fallback seam "
            + "'\(nextURL.lastPathComponent)' (empty prime, scheduleFile)")
    }
}
