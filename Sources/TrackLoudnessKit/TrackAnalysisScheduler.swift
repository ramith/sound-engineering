@preconcurrency import AVFoundation
import Foundation
import Synchronization

/// The album analysis scheduler (R1.1-B W5, lane 3-A; level-and-fold "The store and the scheduler", §13.1; US-R1F-10
/// item 17): it runs the one analysis pass (`TrackAnalysisPass`) over the tracks of the queue's horizon — the albums
/// LevelingKit's `LevelingHorizon` names, never a library sweep — and keeps each result in the analysis store.
///
/// - A track with a current-version record in the store is skipped; one that cannot be analysed is logged once and
///   not tried again this session.
/// - Each call to `setHorizon` replaces the last: a job that left the horizon is cancelled between reads, one that
///   stayed keeps going, and the order of the new list is the order jobs start in.
/// - At most two jobs at once, and one when the work is slower than twice real time (the design's stop rule,
///   §13.1); each track runs at the quality of service `AnalysisQoS` gives its job (the deadline rule, measured).
///
/// Requests return at once, from any thread; the file reads — each file's identity and header, then its decode — run
/// on a global queue, never the main thread or the cooperative pool (review N8: a drive waking up takes seconds).
public final class TrackAnalysisScheduler: Sendable {
    /// One analysis job: a horizon target's files, and how soon the first of them plays.
    public struct Job: Sendable, Equatable {
        /// The job's name, stable across calls for the same target (e.g. "album 42", or a loose track's path).
        public var id: String
        /// The files to analyse, in the order to analyse them (the coordinator puts the queue's next track first).
        public var files: [URL]
        /// Seconds from now until the job's first track plays (0: it is playing). The QoS rule reads it.
        public var startsIn: Double

        public init(id: String, files: [URL], startsIn: Double) {
            self.id = id
            self.files = files
            self.startsIn = startsIn
        }
    }

    private enum Request: Sendable {
        case horizon([Job])
        case stop
    }

    private let inbox: AsyncStream<Request>.Continuation

    /// A scheduler that keeps its results in `store`, logs one line per state change through `log`, and reports
    /// each analysis kept through `onAnalysed` (on its own queue, never main).
    public init(store: TrackAnalysisStore, log: @escaping @Sendable (String) -> Void,
                onAnalysed: @escaping @Sendable (TrackAnalysis) -> Void) {
        let (stream, continuation) = AsyncStream.makeStream(of: Request.self)
        inbox = continuation
        let runner = AnalysisRunner(store: store, log: log, onAnalysed: onAnalysed)
        Task.detached(priority: .utility) {
            for await request in stream {
                switch request {
                case let .horizon(jobs):
                    await runner.setHorizon(jobs)
                case .stop:
                    await runner.setHorizon([])
                }
            }
            await runner.setHorizon([])
        }
    }

    deinit {
        inbox.finish()
    }

    /// The horizon's jobs, most urgent first (LevelingKit's `LevelingHorizon.needs` order). Returns at once.
    public func setHorizon(_ jobs: [Job]) {
        inbox.yield(.horizon(jobs))
    }

    /// Cancel every job (a quit). Returns at once.
    public func stop() {
        inbox.yield(.stop)
    }
}

// MARK: - The QoS rule (lane 3-A's proposal, measured)

/// Which quality of service an analysis job runs at, and how many run at once (R1.1-B W5, lane 3-A; the design's
/// §13.1 stop rule, and lane 1-B's finding that `.background` runs hi-res multichannel at about real time).
///
/// - A job **due** — its first track starts within `dueLead`, the playing album included — runs at `.utility`: its
///   results decide the tracks about to play.
/// - A job further ahead runs at `.background` while its remaining work would still finish there before it is due;
///   otherwise at `.utility`. So typical albums are measured on the efficiency cores, and a hi-res multichannel
///   album, which `.background` cannot finish in time, moves to `.utility` early enough to.
/// - Two jobs at once, one when either of the two most urgent runs slower than `stopRuleSpeed` (§13.1).
///
/// Neither class can delay playback or the interface: Core Audio's IO thread is real-time, the main thread is
/// user-interactive and the app's engine queues run at the default class, all above `.utility` (measured with
/// `scratchpad/r11b/l3a/qos/probe.c`; numbers in lane 3-A's report).
///
/// Work is estimated from the source's sample throughput (rate × channels, which the decode and the Mastering SRC
/// scale with) at a per-class rate measured on an M4 Pro, conservatively, until a job has measured its own.
enum AnalysisQoS {
    /// A job whose first track starts within this many seconds is due.
    static let dueLead = 10.0 * 60
    /// The design's stop rule: a 4-minute track taking over 2 minutes means one job at a time.
    static let stopRuleSpeed = 2.0
    /// Source samples (all channels) analysed per wall second, the slowest measured material per class on an
    /// M4 Pro (release build; scratchpad `qos/measure.log`): `.utility` 6.5 M (44.1 kHz stereo 77×, 192 kHz × 8
    /// 4.4×), `.background` 1.3 M (44.1 kHz stereo 15×, 192 kHz × 8 and DXD 5.0 about 1×).
    static let utilityThroughput = 6.5e6
    static let backgroundThroughput = 1.3e6

    /// What the rule knows of one job.
    struct Work: Equatable {
        /// Seconds until its first track plays.
        var startsIn: Double
        /// Seconds of audio still to analyse.
        var remainingSeconds: Double
        /// The source's samples per second over all channels (the most demanding of its files).
        var samplesPerSecond: Double
        /// Its own measured speed (seconds of audio per wall second) at each class, once it has one.
        var measuredUtility: Double?
        var measuredBackground: Double?
    }

    /// The class `work` runs at now.
    static func qos(for work: Work) -> DispatchQoS.QoSClass {
        guard work.startsIn > dueLead else { return .utility }
        let backgroundSeconds = work.remainingSeconds / speed(of: work, at: .background)
        return backgroundSeconds <= work.startsIn - dueLead ? .background : .utility
    }

    /// How many of `jobs` (most urgent first) may run at once: two, or one when either of the first two is slower
    /// than the stop rule at the class it runs at.
    static func concurrency(_ jobs: [Work]) -> Int {
        jobs.prefix(2).contains { speed(of: $0, at: qos(for: $0)) < stopRuleSpeed } ? 1 : 2
    }

    /// Seconds of audio per wall second for `work` at `qos`: measured, else the model's.
    static func speed(of work: Work, at qos: DispatchQoS.QoSClass) -> Double {
        let samples = max(work.samplesPerSecond, 1)
        if qos == .background {
            return work.measuredBackground ?? backgroundThroughput / samples
        }
        return work.measuredUtility ?? utilityThroughput / samples
    }
}

// MARK: - The runner

/// The scheduler's state: the horizon, the running jobs, their progress, the failures. One actor; the decodes run
/// elsewhere.
private actor AnalysisRunner {
    /// A job's files still to analyse, and what it has measured.
    private struct Progress {
        var job: TrackAnalysisScheduler.Job
        var pending: [Pending]
        var measured: [DispatchQoS.QoSClass: (audio: Double, wall: Double)] = [:]

        var work: AnalysisQoS.Work {
            let speed = { (qos: DispatchQoS.QoSClass) in measured[qos].map { $0.audio / max($0.wall, 1e-6) } }
            return AnalysisQoS.Work(startsIn: job.startsIn, remainingSeconds: pending.map(\.seconds).reduce(0, +),
                                    samplesPerSecond: pending.map(\.samplesPerSecond).max() ?? 0,
                                    measuredUtility: speed(.utility), measuredBackground: speed(.background))
        }
    }

    /// One file of a job not yet analysed, with what its header says.
    private struct Pending {
        let url: URL
        let identity: TrackIdentity
        let seconds: Double
        let samplesPerSecond: Double
    }

    private let store: TrackAnalysisStore
    private let log: @Sendable (String) -> Void
    private let onAnalysed: @Sendable (TrackAnalysis) -> Void
    private var horizon: [TrackAnalysisScheduler.Job] = []
    private var progress: [String: Progress] = [:]
    /// The jobs whose files are being looked at (`prepare`), by the files: a job is looked at once at a time.
    private var preparing: [String: [URL]] = [:]
    private var running: [String: (task: Task<Void, Never>, cancel: CancelFlag)] = [:]
    private var failed: Set<TrackIdentity> = []

    init(store: TrackAnalysisStore, log: @escaping @Sendable (String) -> Void,
         onAnalysed: @escaping @Sendable (TrackAnalysis) -> Void) {
        self.store = store
        self.log = log
        self.onAnalysed = onAnalysed
    }

    /// The new horizon: cancel what left it, keep what stayed (with its new start time), start what may.
    func setHorizon(_ jobs: [TrackAnalysisScheduler.Job]) async {
        let ids = Set(jobs.map(\.id))
        for (id, run) in running where !ids.contains(id) {
            run.cancel.raise()
            run.task.cancel()
            running[id] = nil
        }
        horizon = jobs
        let byID = Dictionary(jobs.map { ($0.id, $0) }) { first, _ in first }
        progress = progress.compactMapValues { kept in
            guard let job = byID[kept.job.id] else { return nil }
            guard job.files == kept.job.files else { return nil } // other files: prepared again
            var updated = kept
            updated.job = job
            return updated
        }
        await startWhatMay()
    }

    /// Start jobs in horizon order while the concurrency rule allows. Re-checks after each suspension: another call
    /// may have changed the horizon or started the job meanwhile. A job whose files are still being looked at by
    /// another call is passed over; that call starts it.
    private func startWhatMay() async {
        for job in horizon where running[job.id] == nil {
            if progress[job.id] == nil {
                guard preparing[job.id] != job.files else { continue }
                preparing[job.id] = job.files
                let pending = await Self.prepare(job, store: store, skipping: failed)
                if preparing[job.id] == job.files {
                    preparing[job.id] = nil
                }
                // Kept for the job as the horizon has it now (its start time moves), if its files are the same.
                guard let current = horizon.first(where: { $0.id == job.id }), current.files == job.files,
                      progress[job.id] == nil else { continue }
                progress[job.id] = Progress(job: current, pending: pending)
            }
            guard running[job.id] == nil, let prepared = progress[job.id], !prepared.pending.isEmpty else { continue }
            guard mayRun(job.id) else { return }
            let cancel = CancelFlag()
            let id = job.id
            running[id] = (Task.detached(priority: .utility) { [weak self] in await self?.run(id, cancel: cancel) },
                           cancel)
        }
    }

    /// Whether job `id` may run (or go on running): it is among the jobs the concurrency rule allows, most urgent
    /// first among those with work left.
    private func mayRun(_ id: String) -> Bool {
        let candidates = horizon.compactMap { job in progress[job.id].flatMap { $0.pending.isEmpty ? nil : $0 } }
        let allowed = AnalysisQoS.concurrency(candidates.map(\.work))
        return candidates.prefix(allowed).contains { $0.job.id == id }
    }

    /// Run job `id` track by track until it is done, cancelled, or no longer allowed to run.
    private func run(_ id: String, cancel: CancelFlag) async {
        while !cancel.isRaised, mayRun(id), let next = progress[id]?.pending.first, let work = progress[id]?.work {
            let qos = AnalysisQoS.qos(for: work)
            let started = ContinuousClock.now
            let outcome = await Self.analyse(next, qos: qos, cancel: cancel)
            let wall = started.duration(to: .now)
            guard !cancel.isRaised else { break }
            await finished(next, outcome: outcome, in: id, qos: qos,
                           wallSeconds: Double(wall.components.seconds) + Double(wall.components.attoseconds) * 1e-18)
        }
        if running[id]?.cancel === cancel {
            running[id] = nil
        }
        await startWhatMay()
    }

    private func finished(_ track: Pending, outcome: TrackAnalysisPass.Outcome, in id: String,
                          qos: DispatchQoS.QoSClass, wallSeconds: Double) async {
        let name = track.url.lastPathComponent
        if case .cancelled = outcome {
            return
        }
        progress[id]?.pending.removeAll { $0.identity == track.identity }
        switch outcome {
        case let .analysed(analysis, _):
            let previous = progress[id]?.measured[qos] ?? (0, 0)
            progress[id]?.measured[qos] = (previous.audio + track.seconds, previous.wall + wallSeconds)
            do {
                try await store.save(analysis)
                onAnalysed(analysis)
                log("analysis: '\(name)' analysed at \(qos == .background ? "background" : "utility") — "
                    + String(format: "%.1f× real time", track.seconds / max(wallSeconds, 1e-6)))
            } catch {
                log("analysis: '\(name)' analysed but not kept — \(error)")
            }
        case let .failed(reason):
            failed.insert(track.identity)
            log("analysis: cannot analyse '\(name)' — \(reason)")
        case .cancelled:
            break
        }
    }

    /// A job's files that still need the pass: each one's identity read, the store's current records skipped, and
    /// each one's length and sample rate read from its header — the file reads on a global queue (`offPool`).
    private static func prepare(_ job: TrackAnalysisScheduler.Job, store: TrackAnalysisStore,
                                skipping failed: Set<TrackIdentity>) async -> [Pending] {
        let named = await offPool(qos: .utility) {
            job.files.compactMap { url in TrackIdentity(url: url).map { (url, $0) } }
        }.filter { !failed.contains($0.1) }
        let kept = (try? await store.analyses(for: named.map(\.1))) ?? [:]
        let unanalysed = named.filter { kept[$0.1] == nil }
        return await offPool(qos: .utility) { unanalysed.compactMap(header) }
    }

    /// The file `url` (identity `identity`) as its header describes it; nil when it cannot be opened.
    private static func header(_ url: URL, _ identity: TrackIdentity) -> Pending? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.fileFormat
        return Pending(url: url, identity: identity, seconds: Double(file.length) / format.sampleRate,
                       samplesPerSecond: format.sampleRate * Double(format.channelCount))
    }

    /// The one analysis pass over `track`, on the global queue of `qos`, while the caller's task awaits.
    private static func analyse(_ track: Pending, qos: DispatchQoS.QoSClass,
                                cancel: CancelFlag) async -> TrackAnalysisPass.Outcome {
        await offPool(qos: qos) {
            TrackAnalysisPass.analyse(track.url, identity: track.identity, isCancelled: { cancel.isRaised })
        }
    }

    /// `work` — blocking file reads — on the global queue of `qos` while the caller's task awaits: no thread of the
    /// cooperative pool waits on a drive.
    private static func offPool<Value: Sendable>(qos: DispatchQoS.QoSClass,
                                                 _ work: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: qos).async {
                continuation.resume(returning: work())
            }
        }
    }
}

/// A cancellation the decode thread can see: `Task.isCancelled` belongs to the task, not the queue.
private final class CancelFlag: Sendable {
    private let raised = Atomic<Bool>(false)

    var isRaised: Bool {
        raised.load(ordering: .acquiring)
    }

    func raise() {
        raised.store(true, ordering: .releasing)
    }
}
