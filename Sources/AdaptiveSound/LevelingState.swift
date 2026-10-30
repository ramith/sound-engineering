import Foundation
import LevelingKit
import TrackLoudnessKit

// MARK: - The leveling coordinator's state (R1.1-B W5, lane 3-B; level-and-fold §S3)

/// What the view model's leveling coordinator (`AudioViewModel+Leveling`) keeps between the requests it makes: the
/// analysis it reads and fills (the store, its scheduler), what it knows of the queue's horizon (the decision
/// builder's input, prefetched off the main thread on every queue change), and the decisions the engine has — the
/// song playing's, which a song that runs on from it at a continuous seam inherits, and the armed pick's.
///
/// Main actor only. Observable for the one thing a view reads: `playing`, the song playing's decision (the
/// Settings row's source).
@MainActor
@Observable
final class LevelingState {
    /// A decision the engine has, for the song `key`.
    struct Sent: Equatable {
        /// The song (`LevelingSlot.key`).
        let key: String
        let decision: TrackLevelingDecision
        /// Whether the song becomes (or became) audible at a seam rather than a fresh start.
        let atSeam: Bool
        /// The song heard before it (Auto's neighbour; continuity's other side at a seam).
        let previous: String?
    }

    /// The song playing (or paused, or starting): the decision it was started or armed with, or the mode change's
    /// since. Nil before the first start.
    private(set) var playing: Sent?

    /// The armed pick's decision (`setNextTrack`), nil when nothing is armed.
    @ObservationIgnored var armed: Sent?
    /// The seam count when the pick was armed: a seam since makes it the song playing.
    @ObservationIgnored var armedAtTransition: UInt64 = 0

    /// What is known of the horizon (`LevelingLoad`).
    @ObservationIgnored var knowledge = LevelingKnowledge()

    /// The analysis store (`track-analysis.sqlite3` beside the library) and its scheduler, once opened; nil in a
    /// view model that has none (tests, the picture sheets), where every song is unanalysed.
    @ObservationIgnored private(set) var store: TrackAnalysisStore?
    @ObservationIgnored private(set) var scheduler: TrackAnalysisScheduler?
    /// The sources a test reads instead of the app's (`StoreLevelingSources`).
    @ObservationIgnored var testSources: (any LevelingSources)?

    /// The clock the start's wait runs on: `ContinuousClock` in the app, a test clock in a test.
    @ObservationIgnored var clock: any Clock<Duration> = ContinuousClock()
    /// How long a start waits for a song whose record is still being read (§S3 "the prefetch").
    static let startWait: Duration = .milliseconds(50)

    /// The horizon's refresh: its number (only the newest lands), and whether one is waiting to run.
    @ObservationIgnored private var refreshGeneration: UInt64 = 0
    @ObservationIgnored var refreshScheduled = false
    /// The queue is followed (`followQueueForLeveling`).
    @ObservationIgnored var followsQueue = false

    /// A start sent `decision` for `key`, or the armed pick became audible at a seam, or a mode change replaced it.
    func play(_ sent: Sent) {
        if playing != sent {
            playing = sent
        }
    }

    /// The store and its scheduler, once opened.
    func attach(store: TrackAnalysisStore, scheduler: TrackAnalysisScheduler) {
        self.store = store
        self.scheduler = scheduler
    }

    /// A new refresh of the horizon: its number.
    func beginRefresh() -> UInt64 {
        refreshGeneration &+= 1
        return refreshGeneration
    }

    /// Whether `generation` is still the newest refresh (an older one's result is dropped).
    func isNewest(_ generation: UInt64) -> Bool {
        generation == refreshGeneration
    }
}
