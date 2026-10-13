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
/// calls, the device-loss teardown) runs there too, so a sample never interleaves with one, and each
/// of them publishes a fresh sample before it returns — a reader after `await startAudio` sees the
/// new track's seam count and a cleared end flag, never the clock's last pre-start sample.
extension AudioEngineBridge {
    /// How often the clock samples: a bit faster than the 20 Hz tick, so a tick is at most one
    /// sample (~33 ms) behind the hardware.
    private static let clockInterval = DispatchTimeInterval.milliseconds(33)

    /// Start sampling (on `engineQueue`, from `initialize()`). Idempotent.
    func startTransportClock() {
        guard transportClock == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: engineQueue)
        timer.schedule(deadline: .now(), repeating: Self.clockInterval, leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            self?.sampleTransport()
        }
        timer.resume()
        transportClock = timer
    }

    /// Stop sampling (engine teardown, on `engineQueue`). The last sample stays readable.
    func stopTransportClock() {
        transportClock?.cancel()
        transportClock = nil
    }

    /// Sample the active path and publish it. On `engineQueue` only: the clock's handler, and the end
    /// of every start / stop / seek, so the tick's next read reflects them.
    func sampleTransport() {
        dispatchPrecondition(condition: .onQueue(engineQueue))
        transportSnapshots.publish(liveTransport())
    }

    /// The live reads. These may wait — on the player's lock, on `resampleQueue`, on the HAL — and
    /// that is fine here, never on the main thread.
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
        // Enhanced: the player's playhead, then the seam count and end flag (atomics — the clock
        // never waits on resampleQueue, which can be busy in AVFAudio or opening the next file).
        // Playhead first, for the same reason as Pure: a seam (`bumpTransitionCount` counts, then
        // re-bases) between the reads shows as the old track's end then the advance.
        let position = liveEnhancedPosition()
        return TransportSnapshot(position: position, transitionCount: gaplessTransitionCount,
                                 ended: gaplessPlaybackEnded)
    }

    /// The Enhanced playhead, read from the player — NEVER on the main thread (enforced): these
    /// AVFAudio calls take the engine's lock, which a stop on a dying device can hold for seconds.
    ///
    /// AVAudioPlayerNode's sampleTime counts from 0 at EACH play() — time-since-play, not file
    /// position. A seek does stop() + scheduleSegment(from:) + play(), which restarts sampleTime at
    /// 0, so the seek target (`enhancedPositionBaseSeconds`, 0 on a fresh play) is added back.
    /// Caches the result as the freshest reliable playhead for the configuration-change re-establish.
    func liveEnhancedPosition() -> Double? {
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard let playerNode = playerNodeRef, playerNode.isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0
        else {
            return nil
        }
        let position = enhancedPositionBaseSeconds + Double(playerTime.sampleTime) / playerTime.sampleRate
        setLastKnownEnhancedPositionSeconds(position)
        return position
    }
}
