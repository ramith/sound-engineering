@preconcurrency import AVFoundation
import Foundation
import PlaybackQueueKit

// MARK: - AudioEngineBridge transport clock (the main thread reads a copy)

/// The transport facts the view model's 20 Hz tick needs — the playhead, the seam count, the end of
/// the queue — sampled OFF the main thread and handed over as a `TransportSnapshot` copy.
///
/// Why (S10.8 G, the disconnect freeze): the tick used to read them live on the main thread —
/// `-[AVAudioPlayerNode isPlaying]` / `playerTime(forNodeTime:)` and `resampleQueue.sync`. When
/// headphones switched off, macOS held the dying device's lock for ~7 s; the device-loss
/// `player.stop()` waited on it (in `GetDeviceLatency`) while holding the player's lock, and the
/// tick's `isPlaying` waited on that lock: a 3–7 s beach ball. Now the clock does those reads on
/// `engineQueue`; when they wait, the snapshot just goes stale and the main thread never notices.
///
/// The clock runs on `engineQueue` on purpose: every transport change (start, stop, seek, the Pure
/// calls, the device-loss teardown) runs there too, so a sample never interleaves with one. Each
/// change first publishes a transitional sample stamped with the request's EPOCH (before any slow
/// work: a Pure rate change can take seconds), and a settled sample before it returns. The view
/// model numbers its requests and ignores older samples (`TransportSnapshot.isCurrent(for:)`), so
/// it never acts on the playback a request replaces — the old track's end flag, its playhead.
///
/// The clock runs only while something plays (from a start until the stop, the device-loss pause
/// or the teardown), not 30 times a second forever.
extension AudioEngineBridge {
    /// How often the clock samples while playing: a bit faster than the 20 Hz tick.
    private static let clockInterval = DispatchTimeInterval.milliseconds(33)

    /// Start sampling (on `engineQueue`, at every start). Idempotent.
    func startTransportClock() {
        dispatchPrecondition(condition: .onQueue(engineQueue))
        guard transportClock == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: engineQueue)
        timer.schedule(deadline: .now(), repeating: Self.clockInterval, leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            self?.sampleTransport()
        }
        timer.resume()
        transportClock = timer
    }

    /// Stop sampling (on `engineQueue`: a stop, the device-loss pause, the teardown). The caller
    /// publishes a final sample; it stays readable.
    func stopTransportClock() {
        dispatchPrecondition(condition: .onQueue(engineQueue))
        transportClock?.cancel()
        transportClock = nil
    }

    /// The top of a transport operation numbered `epoch` (start, seek, stop), on `engineQueue`,
    /// before any slow work: publish its transitional sample — the place it goes to (`nil`: not
    /// known yet), no end flag, the seam count the reader last saw (a count from the replaced
    /// playback must not read as a seam) — and stamp every later sample with `epoch`.
    func beginTransportOperation(epoch: UInt64, position: Double?) {
        dispatchPrecondition(condition: .onQueue(engineQueue))
        transportEpoch = max(transportEpoch, epoch)
        let seen = transportSnapshots.read()
        transportSnapshots.publish(TransportSnapshot(epoch: transportEpoch, position: position,
                                                     transitionCount: seen.transitionCount, ended: false))
    }

    /// Sample the active path and publish it. On `engineQueue` only: the clock's handler, and the end
    /// of every start / stop / seek, so the tick's next read reflects them.
    func sampleTransport() {
        dispatchPrecondition(condition: .onQueue(engineQueue))
        var sample = liveTransport()
        sample.epoch = transportEpoch
        transportSnapshots.publish(sample)
    }

    /// The live reads. These may wait — on the engine's lock, on the HAL — and that is fine here,
    /// never on the main thread.
    private func liveTransport() -> TransportSnapshot {
        // Pure: the HAL GaplessSource's playhead, seam count (the poll also reaps a seam-retired
        // decode source off-RT, which is why it is polled every sample) and end flag. Position first:
        // a seam between the two reads shows as the old track's end then the advance, never a 0:00
        // under the old track.
        if let pure = withPureEngine({ handle in
            (position: pureModeEnginePositionSeconds(handle),
             count: pureModeEnginePollTrackAdvance(handle),
             ended: pureModeEnginePlaybackEnded(handle) == 1)
        }) {
            return TransportSnapshot(position: pure.position > 0 ? pure.position : nil,
                                     transitionCount: pure.count, ended: pure.ended)
        }
        // Enhanced: the player's playhead between two reads of the seam count (atomics — the clock
        // never waits on resampleQueue, which can be busy in AVFAudio or opening the next file). A
        // seam (`bumpTransitionCount`: count, then re-base) landing in between leaves the playhead
        // unknown for this one sample, and the seam's re-zeroed last-known playhead untouched.
        let countBefore = gaplessTransitionCount
        let position = liveEnhancedPosition()
        let count = gaplessTransitionCount
        guard count == countBefore else {
            return TransportSnapshot(position: nil, transitionCount: count, ended: gaplessPlaybackEnded)
        }
        if let position {
            setLastKnownEnhancedPositionSeconds(position) // the freshest reliable playhead (re-establish)
        }
        return TransportSnapshot(position: position, transitionCount: count, ended: gaplessPlaybackEnded)
    }

    /// The Enhanced playhead, read from the player — NEVER on the main thread (enforced): these
    /// AVFAudio calls take the engine-wide lock, which a stop or start can hold for seconds.
    ///
    /// AVAudioPlayerNode's sampleTime counts from 0 at EACH play() — time-since-play, not file
    /// position. A seek does stop() + scheduleSegment(from:) + play(), which restarts sampleTime at
    /// 0, so the seek target (`enhancedPositionBaseSeconds`, the start place on a fresh play) is
    /// added back. Never negative.
    func liveEnhancedPosition() -> Double? {
        dispatchPrecondition(condition: .notOnQueue(.main))
        // Between the first start + play and the first render, `lastRenderTime` exists but holds
        // neither a valid sample time nor a valid host time, and `playerTime(forNodeTime:)` then
        // raises an exception (AVFAudio: "nodeTime == nil || nodeTime.sampleTimeValid ||
        // nodeTime.hostTimeValid"). Check first.
        guard let playerNode = playerNodeRef, playerNode.isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              nodeTime.isSampleTimeValid || nodeTime.isHostTimeValid,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0
        else {
            return nil
        }
        return max(enhancedPositionBaseSeconds + Double(playerTime.sampleTime) / playerTime.sampleRate, 0)
    }
}
