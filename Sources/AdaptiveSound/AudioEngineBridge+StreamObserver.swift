@preconcurrency import AVFoundation
import Foundation

// MARK: - AudioEngineBridge: what the Enhanced path has scheduled, told to an observer (test seam)

/// Hears what the Enhanced path schedules on the player and when AVFAudio's completion for it has been
/// handed on. `nil` in the app. A test rig installs one so it can render in lock-step with the completion
/// chain: AVFAudio reports a buffer consumed some 150 µs AFTER the render that consumed it, on a thread of
/// its own, so a rig that renders on without waiting races the chain (a block's sleep merely hoped).
/// With the frames scheduled and the completions delivered, a rig knows exactly which completions are due
/// after a render and waits for them (R4).
protocol StreamObserver: AnyObject, Sendable {
    /// `frames` were scheduled on the player, to be reported consumed in order. Returns the token the
    /// delivery will carry.
    func scheduled(frames: Int64) -> Int
    /// The completion for `token` has been handed on: its `resampleQueue` work is queued.
    func delivered(_ token: Int)
    /// Everything scheduled so far is superseded (a stop, a seek): its completions are not owed.
    func superseded()
}

extension AudioEngineBridge {
    /// `completion`, reported to the observer (if there is one) as scheduled now for `frames` frames and
    /// delivered once it has run. A completion only queues its work on `resampleQueue`, so "delivered" is
    /// reported after that work is queued — a drain of the queue then runs it.
    func observed(frames: Int64, _ completion: @escaping Completion) -> Completion {
        guard let observer = streamObserver.withLock({ $0 }) else { return completion }
        let token = observer.scheduled(frames: frames)
        return { type in
            completion(type)
            observer.delivered(token)
        }
    }

    /// Tell the observer, if any, that what was scheduled so far is superseded.
    func supersedeObservedSchedule() {
        streamObserver.withLock { $0 }?.superseded()
    }
}
