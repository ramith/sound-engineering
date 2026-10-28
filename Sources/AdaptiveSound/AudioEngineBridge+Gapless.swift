import AudioDSP
@preconcurrency import AVFoundation
import Foundation
import LevelingKit
import PlaybackQueueKit

// MARK: - AudioEngineBridge Enhanced-path gapless engine

/// Gapless on the Enhanced path (the engine graph + streaming resampler): `setNextTrack`, and the
/// seam count and end-of-queue flag the transport clock publishes in `TransportSnapshot`.
///
/// ## Architecture overview
///
/// Two sub-paths exist on the Enhanced path, and gapless is handled differently for each:
///
/// **Resampler sub-path** (file rate ≠ 48 kHz, driven by `AudioEngineBridge+EnhancedResampler`):
///   The `onResamplerEOF` hook is installed on `resampleQueue` when a next track is armed. A next
///   track of the SAME format never needs it: once the playing file runs out, the reader takes the
///   next one and its frames continue the stream through the same converter
///   (`continueStreamIntoNextTrack`); the seam is counted when the player reaches the join
///   (`commitJoin`). Otherwise, when the resampler's completion chain reaches end-of-file it fires
///   the hook (still on `resampleQueue`): `rollResamplerToNext` opens the new file, builds a NEW
///   resampler session, and primes it (`primeEnhancedResamplerLocked`) without stopping the player.
///   With nothing armed, the stream's end is its last buffer's, once heard (`streamPlayedOut`) —
///   as on the passthrough sub-path, so the stop at the end of the queue cuts nothing (S-1).
///
/// **Passthrough sub-path** (48 kHz file, `scheduleFile`):
///   `commitEnhanced` schedules the file with `completionCallbackType: .dataPlayedBack` (rendered,
///   offline: `playedBackCallbackType`) and dispatches onto `resampleQueue` when the hardware
///   finishes playing the last sample. `onPassthroughEOF`
///   fires there. If a next track is armed and it is also 48 kHz → `scheduleFile` the new file
///   immediately (consecutive schedules play back-to-back, byte-exact); if the next track is a
///   different rate → a new resampler session for it, primed without stopping the player.
///
/// ## Thread model
///
/// The gapless seam state (`onDeckURL`, `onResamplerEOF`, `onPassthroughEOF`) is read and
/// written only on `resampleQueue`, the serial queue that owns the resampler/converter state; an
/// admitted `setNextTrack` hands it there from `engineQueue` (`armEnhancedOnDeck`). The seam count
/// and end flag (`gaplessTransitionCount`, `gaplessPlaybackEnded`) are written there too, but they
/// are named acquire/release atomics: the transport clock reads them on `engineQueue` and publishes
/// them in the `TransportSnapshot` copy. The main thread never reads them, nor syncs onto
/// `resampleQueue` (S10.8 G).
///
/// ## Gapless AAC/MP3 note
///
/// `AVAudioFile` / `ExtAudioFile` automatically trims AAC priming silence and MP3 LAME delay/
/// padding (via the file's edit list and `kExtAudioFileProperty_ClientDataFormat`). This is
/// Apple's responsibility on the Enhanced path; we must not disable or override it. The explicit
/// FFmpeg-path trim (for the Pure path) is Stage 2.
extension AudioEngineBridge {
    // MARK: - Protocol requirements (AudioPlaybackEngine)

    /// Supply (or clear, with `nil`) the track to play gaplessly after the current one: the on-deck
    /// request numbered `ticket` (`AudioPlaybackEngine.setNextTrack`, council D41). On `engineQueue`:
    ///
    /// - **Admission.** Only the newest request of the current playback passes `onDeckGate`; any other
    ///   is dropped and has no effect (a Pure pick is never opened). The path is read here, on the
    ///   queue that changes it, so a request can't be routed to a path a start just replaced.
    /// - **Applied at once.** Enhanced sets the on-deck slot (`armEnhancedOnDeck`). Pure takes the old
    ///   pick off now and arms the new one once its file opens, if it is still the newest
    ///   (`retractThenArmPure`).
    ///
    /// A seek does not consume the on-deck track; a start or stop begins a new playback (every
    /// earlier request is stale). Returns once the request is settled: dropped, set, or armed / left
    /// empty. Safe to call from any thread.
    func setNextTrack(_ fileURL: URL?, ticket: OnDeckTicket, leveling _: TrackLevelingDecision?) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            engineQueue.async {
                guard self.onDeckGate.admit(ticket) else {
                    logUX("setNextTrack '\(fileURL?.lastPathComponent ?? "none")' (\(ticket)) → stale, dropped")
                    continuation.resume()
                    return
                }
                if self.activePathKind == .pure {
                    self.retractThenArmPure(fileURL, ticket: ticket) { continuation.resume() }
                } else {
                    self.armEnhancedOnDeck(fileURL) { continuation.resume() }
                }
            }
        }
    }

    /// The Enhanced arm, for an admitted request (on `engineQueue`): prefetch the pick's loudness
    /// profile, then set the on-deck slot on `resampleQueue` (which owns the seam state) and arm the
    /// EOF hook of the sub-path playing now — or, for `nil`, clear the slot and disarm both hooks so
    /// no stale handler fires. `done` runs once the slot is set.
    ///
    /// `async`, not `sync`: admissions are serialized here and `resampleQueue` is FIFO, so the slot
    /// takes them — and a start's or stop's clear — in admission order, while a seam busy opening the
    /// next file can't hold `engineQueue` (the clock and every transport op) behind it.
    private func armEnhancedOnDeck(_ fileURL: URL?, done: @escaping @Sendable () -> Void) {
        dispatchPrecondition(condition: .onQueue(engineQueue))
        // The engine switches to the profile only when the track becomes AUDIBLE
        // (bumpTransitionCount) — never here.
        prefetchTrackLoudness(fileURL)
        resampleQueue.async {
            defer { done() }
            self.onDeckURL = fileURL
            guard fileURL != nil else {
                self.onResamplerEOF = nil
                self.onPassthroughEOF = nil
                return
            }
            guard let player = self.playerNode else { return }
            if self.resampleSession != nil {
                self.armResamplerNextTrack(player: player)
            } else {
                self.armPassthroughNextTrack(player: player)
            }
        }
    }

    /// The Pure arm, for an admitted request (on `engineQueue`). The old pick comes off now —
    /// `pureModeEngineClearNextTrack` is an exactly-once exchange with the render's seam claim, so it
    /// either already played or never will. The new pick's file opens on a global queue (the
    /// network-slow step, off every bridge queue) and arms back on `engineQueue`, where every Pure
    /// C-ABI call is serialized with the clock, seek and teardown, only if its request is still the
    /// newest. A pick the running stream can't carry, a file that doesn't open, or a track that
    /// already ended leave the slot empty: the current track ends, and the view model starts the pick
    /// fresh (a short gap, the right song). `done` runs once the request is settled.
    private func retractThenArmPure(_ fileURL: URL?, ticket: OnDeckTicket,
                                    done: @escaping @Sendable () -> Void) {
        dispatchPrecondition(condition: .onQueue(engineQueue))
        _ = withPureEngine { pureModeEngineClearNextTrack($0) }
        guard let url = fileURL else {
            logUX("pure setNextTrack none (\(ticket)) → cleared")
            done()
            return
        }
        logUX("pure setNextTrack '\(url.lastPathComponent)' (\(ticket)) → old pick retracted, opening")
        DispatchQueue.global().async {
            guard let decoder = Self.openPureDecoder(url) else {
                logUX("pure setNextTrack '\(url.lastPathComponent)' (\(ticket)) → error (open failed)")
                done()
                return
            }
            // Hand the opened decoder to engineQueue by its address (a C handle; the ownership
            // moves with it): no worker blocks while a transport change finishes there.
            let decoderAddress = UInt(bitPattern: decoder)
            self.engineQueue.async {
                self.armOpenedPure(decoderAddress: decoderAddress, url: url, ticket: ticket)
                done()
            }
        }
    }

    /// Arm a decoder opened for `ticket` (on `engineQueue`), if that request is still the newest
    /// and Pure still plays; otherwise free it.
    private func armOpenedPure(decoderAddress: UInt, url: URL, ticket: OnDeckTicket) {
        guard let decoder = UnsafeMutableRawPointer(bitPattern: decoderAddress) else { return }
        guard onDeckGate.isCurrent(ticket) else {
            pureModeDestroyDecodeSource(decoder)
            logUX("pure setNextTrack '\(url.lastPathComponent)' (\(ticket)) → superseded, dropped")
            return
        }
        // arm TAKES OWNERSHIP; nil (no longer Pure) ⇒ arm never ran ⇒ free the decoder.
        if let result = withPureEngine({ pureModeEngineArmOpenedNextTrack($0, decoder) }) {
            logUX("pure setNextTrack '\(url.lastPathComponent)' (\(ticket)) → \(Self.pureArmLabel(result))")
        } else {
            pureModeDestroyDecodeSource(decoder)
        }
    }

    /// Open `url` into a Pure decode source under its security scope; `nil` when it can't be read.
    private static func openPureDecoder(_ url: URL) -> UnsafeMutableRawPointer? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return url.path.withCString { pureModeOpenDecodeSource($0) }
    }

    /// Label for a `pureModeEngineArmOpenedNextTrack` result (2 armed / 1 reconfigure / 3 ended /
    /// 0 error).
    private static func pureArmLabel(_ result: Int32) -> String {
        switch result {
        case 2: return "armed (gapless)"
        case 1: return "needs-reconfigure (gap on advance)"
        case 3: return "ended → not armed (fresh start)"
        default: return "error"
        }
    }

    // The seam count and the end flag reach the view model through the transport snapshot
    // (`snapshot()`'s transport, AudioEngineBridge+TransportClock), sampled off the main thread.

    // MARK: - Arm helpers (called on resampleQueue)

    /// Install the `onResamplerEOF` hook for the currently active resampler session.
    /// MUST be called on `resampleQueue`. No-op if no session is active.
    func armResamplerNextTrack(player: AVAudioPlayerNode) {
        onResamplerEOF = { [weak self, weak player] _, _ in
            guard let self, let player else { return }
            self.onResamplerEOF = nil // consume the one-shot hook
            self.rollResamplerToNext(player: player)
        }
    }

    /// Install the `onPassthroughEOF` hook for the current 48 kHz passthrough session.
    /// MUST be called on `resampleQueue`. No-op if the player node is not reachable.
    func armPassthroughNextTrack(player: AVAudioPlayerNode) {
        onPassthroughEOF = { [weak self, weak player] _ in
            guard let self, let livePlayer = player else { return }
            self.onPassthroughEOF = nil // consume the one-shot hook
            self.rollPassthroughToNext(player: livePlayer)
        }
    }

    // MARK: - Position continuity at seams

    /// Bump `gaplessTransitionCount` and reset the position base to re-zero the new track, and
    /// tell the engine `nextURL` is the audible track now (its loudness-neutral EQ gain).
    ///
    /// Called at every real seam (never on seek or stop). Captures the player's current
    /// `sampleTime` to set `enhancedPositionBaseSeconds` so `liveEnhancedPosition()` reports
    /// 0.0 for the first sample of the new track and grows from there.
    ///
    /// N-2 fix: when `playerTime(forNodeTime:)` returns nil (engine reconfiguring at the seam),
    /// use `-lastKnownEnhancedPositionSeconds` as the base. This counteracts the accumulated
    /// sampleTime so `liveEnhancedPosition()` reads ~0 for the new track instead of jumping
    /// to track-A-duration and counting forward from there.
    ///
    /// A seam inside one resampled stream (`commitJoin`) passes `endingTrackSeconds`: the next track
    /// starts exactly where the ending one ends on the player's timeline, so the base moves back by
    /// that track's length — exact, with no estimate from when this runs.
    ///
    /// MUST be called on `resampleQueue` (all gapless state lives there).
    func bumpTransitionCount(player: AVAudioPlayerNode, nextURL: URL, endingTrackSeconds: Double? = nil) {
        gaplessTransitionCounter.wrappingAdd(1, ordering: .acquiringAndReleasing)
        trackBecameAudible(nextURL, gaplessSeam: true)
        if let endingTrackSeconds {
            moveEnhancedPositionBaseSeconds(by: -endingTrackSeconds)
            setLastKnownEnhancedPositionSeconds(0)
            logUX("gapless: seam #\(gaplessTransitionCount) — position re-based by the ending track's length")
            return
        }

        // Capture the player's sampleTime off the audio thread (safe — CoreAudio property read).
        // The player is still running at the seam, so sampleTime is the hardware clock position at
        // the boundary. base = -(sampleTime/rate) → position = base + sampleTime/rate = 0 at seam.
        let nodeTime = player.lastRenderTime
        let pTime = nodeTime.flatMap { player.playerTime(forNodeTime: $0) }
        let baseSeconds: Double
        if let pTime, pTime.sampleRate > 0 {
            baseSeconds = -Double(pTime.sampleTime) / pTime.sampleRate
        } else {
            // N-2: render time unavailable (engine mid-reconfiguration). Use the negative of the
            // last known position so that base + sampleTime/rate ≈ 0 for the new track, rather
            // than jumping forward by the full accumulated sampleTime.
            baseSeconds = -lastKnownEnhancedPositionSeconds
        }
        setEnhancedPositionBaseSeconds(baseSeconds)
        setLastKnownEnhancedPositionSeconds(0)
        logUX("gapless: seam #\(gaplessTransitionCount) — position reset")
    }
}

// The seam handlers (rollResamplerToNext / rollPassthroughToNext) and their shared
// sub-steps live in AudioEngineBridge+GaplessRoll.swift.
