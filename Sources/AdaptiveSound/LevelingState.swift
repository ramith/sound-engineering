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
    /// A decision the engine has, for the song at `url`.
    struct Sent: Equatable {
        /// The song's file, as the engine's requests name it.
        let url: URL
        let decision: TrackLevelingDecision
        /// Whether the song becomes (or became) audible at a seam rather than a fresh start.
        let atSeam: Bool
        /// The song heard before it (Auto's neighbour; continuity's other side at a seam).
        let previous: String?

        /// The song (`LevelingSlot.key`).
        var key: String {
            LevelingSlot.key(of: url)
        }

        /// The decision, named by its song, as a mode change sends it.
        var song: SongLeveling {
            SongLeveling(url: url, decision: decision)
        }

        /// Whether `other` is the same song, reached the same way, playing the same (`playsLike`).
        func playsLike(_ other: Sent) -> Bool {
            url == other.url && atSeam == other.atSeam && previous == other.previous
                && decision.playsLike(other.decision)
        }
    }

    /// The song playing (or paused, or starting): the decision it was started or armed with, or the mode change's
    /// since. Nil before the first start.
    private(set) var playing: Sent?

    /// The armed pick's decision (`setNextTrack`), nil when nothing is armed.
    @ObservationIgnored var armed: Sent?
    /// The seam count when the pick was armed: a seam since makes it the song playing.
    @ObservationIgnored var armedAtTransition: UInt64 = 0

    /// On-deck requests sent (`armOnDeck`) and not yet landed.
    @ObservationIgnored var armsInFlight = 0
    /// A mode change went out while a start or an on-deck request was still on its way, with the old mode's
    /// decision: it is sent again once they have landed.
    @ObservationIgnored var modeChangeOutran = false
    /// The newest mode change on its way to the engine; each waits for the one before, so they apply in order.
    @ObservationIgnored var modeChange: Task<Void, Never>?

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

    /// A start sent `decision` for `key`, or the armed pick became audible at a seam, or a mode change replaced it.
    /// One that plays as the song playing does changes nothing (Observation has no equality gate of its own).
    func play(_ sent: Sent) {
        if playing?.playsLike(sent) != true {
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

extension TrackLevelingDecision {
    /// Whether `other` plays as this does: every number and verdict alike, and saved profiles on the same bases and
    /// grid — never comparing the profiles' band powers (binary16, about 600 KB each), which the main thread would
    /// otherwise walk on every refresh of the horizon, as it reads the profiles again (review N14). A profile is its
    /// measurement's: a new one comes with new numbers.
    func playsLike(_ other: TrackLevelingDecision) -> Bool {
        var (mine, theirs) = (self, other)
        (mine.profiles, theirs.profiles) = ([], [])
        return mine == theirs && profiles.count == other.profiles.count
            && zip(profiles, other.profiles).allSatisfy { $0.isOnTheGridOf($1) }
    }
}

private extension CompactLoudnessProfile {
    /// The same basis and grid — rate, bands, blocks — as `other`, whatever the powers.
    func isOnTheGridOf(_ other: CompactLoudnessProfile) -> Bool {
        basis == other.basis && sampleRate == other.sampleRate && bandsPerOctave == other.bandsPerOctave
            && bandCount == other.bandCount && blockCount == other.blockCount
            && blockStrideHops == other.blockStrideHops && powers.count == other.powers.count
    }
}
