import Foundation

/// The album analysis scheduler (R1.1-B W5, lane 3-A; level-and-fold "The store and the scheduler", §13.1; US-R1F-10
/// item 17): it runs the one analysis pass (`TrackAnalysisPass`) over the tracks of the queue's horizon — the albums
/// LevelingKit's `LevelingHorizon` names, never a library sweep — and keeps each result in the analysis store.
///
/// - At most two jobs at once; a track with a current-version record in the store is skipped.
/// - Each call to `setHorizon` replaces the last: a job that left the horizon is cancelled between reads.
/// - The QoS rule (which jobs run at which quality of service, and when one job instead of two) is lane 3-A's,
///   measured; see `TrackAnalysisScheduler`'s implementation notes.
///
/// Requests return at once, from any thread; the work runs on queues of its own, never the main thread or the
/// cooperative pool.
public final class TrackAnalysisScheduler: Sendable {
    /// One analysis job: a horizon target's files, and how soon the first of them plays.
    public struct Job: Sendable, Equatable {
        /// The job's name, stable across calls for the same target (e.g. "album 42", or a loose track's path).
        public var id: String
        /// The files to analyse, in the order they play (an album's running order).
        public var files: [URL]
        /// Seconds from now until the job's first track plays (0: it is playing). The QoS rule reads it.
        public var startsIn: Double

        public init(id: String, files: [URL], startsIn: Double) {
            self.id = id
            self.files = files
            self.startsIn = startsIn
        }
    }

    /// A scheduler that keeps its results in `store`, logs one line per state change through `log`, and reports
    /// each analysis kept through `onAnalysed` (on its own queue, never main). Lane 3-A's scheduler (stub until it
    /// lands).
    public init(store _: TrackAnalysisStore, log _: @escaping @Sendable (String) -> Void,
                onAnalysed _: @escaping @Sendable (TrackAnalysis) -> Void) {}

    /// The horizon's jobs, most urgent first (LevelingKit's `LevelingHorizon.needs` order). Returns at once.
    public func setHorizon(_: [Job]) {}

    /// Cancel every job (a quit). Returns at once.
    public func stop() {}
}
