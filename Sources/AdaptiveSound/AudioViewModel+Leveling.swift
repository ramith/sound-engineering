import Foundation
import LevelingKit
import Observation
import PlaybackQueueKit
import SettingsKit
import TrackLoudnessKit

// MARK: - AudioViewModel: the leveling coordinator (R1.1-B W5, lane 3-B; level-and-fold §S3)

//
// Every request that can make a song audible carries its leveling decision (B2): a start (`startAudio(…, leveling:)`)
// and the armed pick (`setNextTrack(…, leveling:)`), and a listener's mode change replaces both
// (`applyLevelingChange(current:next:)`). The decisions are LevelingKit's (`LevelingLibrary.decision(for:)`, lane
// 3-A); this coordinator gathers what the builder reads and hands its answer on — it never substitutes one of its
// own (an Off decision still carries the song's measured peaks: the fold's trim and the peak cap need them).
//
// WHAT THE BUILDER READS is prefetched off the main thread on every queue change (`LevelingLoad.horizon`): for the
// queue's horizon (LevelingKit's `LevelingHorizon`: the current album and the next ~2 hours, never a library sweep),
// each song's analysis from the store or else its tags, every member of the albums it needs, and the saved profiles
// of the current and next songs. The same pass tells the scheduler which albums to analyse.
//
// THE 50 MS WAIT. A start whose song the prefetch has not looked up yet looks it up alone and waits at most 50 ms
// for it; then it starts with what is known — the unknown cut, if nothing (§S3). The song never waits longer.
//
// NOTHING AUTOMATIC MOVES THE LEVEL INSIDE A SONG (US-R1F-10 item 4). An analysis that lands mid-song takes effect at
// the next song: the armed pick is re-armed with it while it is still well ahead (`rearmIfTheArmedDecisionChanged`).
// Only the listener's mode change re-plans the song playing, with the planner's 0.15 s glide (item 19).

@MainActor
extension AudioViewModel {
    /// The Kit's mode for the listener's setting.
    var levelingMode: LevelingMode {
        LevelingMode(leveling)
    }

    // MARK: - Setting up

    /// At init: follow the queue for the horizon, and hear Pure give a device's volume back ("Volume restored").
    func startLevelingCoordination() {
        engine.reportPureVolumeRestores { [weak self] in self?.pureVolumeRestored() }
        followQueueForLeveling()
    }

    /// Open the analysis store in `directory` (the app's data folder) and its scheduler, off the main thread
    /// (composition root, Edge 6). A store that cannot be opened leaves every song unanalysed, logged.
    func openLevelingAnalysis(in directory: URL) {
        work.spawnDetached(priority: .utility) { [weak self] in
            let store: TrackAnalysisStore
            do {
                store = try TrackAnalysisStore(directory: directory)
            } catch {
                logUX("leveling: the analysis store could not be opened (\(error)) — every song plays unanalysed")
                return
            }
            await self?.attachLevelingAnalysis(store)
        }
    }

    /// Use `store` (and a scheduler over it) for what leveling reads.
    func attachLevelingAnalysis(_ store: TrackAnalysisStore) {
        let scheduler = TrackAnalysisScheduler(
            store: store, log: { logUX("analysis: \($0)") },
            onAnalysed: { [weak self] _ in Task { @MainActor in self?.scheduleLevelingRefresh() } }
        )
        levelingState.attach(store: store, scheduler: scheduler)
        logUX("leveling: analysis store open at \(store.url.path)")
        scheduleLevelingRefresh()
    }

    /// What leveling reads: a test's own sources, or the analysis store and the library's; nil while neither
    /// exists (a view model with no store: every song unanalysed, nothing to look up).
    var levelingSources: (any LevelingSources)? {
        if let sources = levelingState.testSources {
            return sources
        }
        let library = library?.store
        guard levelingState.store != nil || library != nil else { return nil }
        return StoreLevelingSources(analysis: levelingState.store, library: library)
    }

    // MARK: - Following the queue (the prefetch)

    /// Refresh the horizon whenever the play order changes — the queue, the song playing, shuffle, repeat — or the
    /// library's store opens. Observation fires once per registration: each refresh registers again.
    func followQueueForLeveling() {
        withObservationTracking {
            _ = queue
            _ = selectedTrackIndex
            _ = shuffleEnabled
            _ = repeatMode
            _ = library?.store
        } onChange: { [weak self] in
            // The view model's state changes on the main actor only.
            MainActor.assumeIsolated { self?.scheduleLevelingRefresh() }
        }
    }

    /// One refresh at the end of this turn, however many changes the turn made.
    func scheduleLevelingRefresh() {
        guard !levelingState.refreshScheduled else { return }
        levelingState.refreshScheduled = true
        work.spawn { [self] in
            levelingState.refreshScheduled = false
            followQueueForLeveling()
            await refreshLevelingHorizon()
        }
    }

    /// Look up the horizon off the main thread; the newest lookup's result replaces what was known, the scheduler
    /// gets its jobs, and an armed pick whose decision changed is re-armed.
    func refreshLevelingHorizon() async {
        guard let sources = levelingSources else { return }
        let upcoming = upcomingLevelingSlots()
        let generation = levelingState.beginRefresh()
        let knowledge = await LevelingLoad(sources: sources, previous: levelingState.knowledge)
            .horizon(upcoming, profilesFor: Set(upcoming.prefix(2).map(\.key)))
        guard levelingState.isNewest(generation) else { return }
        levelingState.knowledge = knowledge
        levelingState.scheduler?.setHorizon(knowledge.jobs)
        rearmIfTheArmedDecisionChanged()
    }

    /// The play order from the selected song, each slot once, as far as it goes (`limit`): the queue's order, or
    /// shuffle's pass; Repeat All's wrap until a slot comes round again; Repeat One the song alone.
    func upcomingLevelingSlots(limit: Int = 400) -> [LevelingSlot] {
        guard let start = selectedTrackIndex, start < queue.count else { return [] }
        let rows = Dictionary(queue.indices.map { (queue[$0].id, $0) }, uniquingKeysWith: { first, _ in first })
        var order = [start]
        var seen: Set<UUID> = [queue[start].id]
        var pass = shufflePass
        var row = start
        while order.count < limit,
              let next = playbackOrder.next(after: row, count: queue.count, pass: pass, row: { rows[$0] }),
              next < queue.count, seen.insert(queue[next].id).inserted {
            pass?.arrive(at: queue[next].id)
            order.append(next)
            row = next
        }
        return order.map { levelingSlot(queue[$0].file) }
    }

    /// The song after `row` in play order, from the song playing (Auto's "next" for a pick armed at `row`).
    private func levelingSlot(after row: Int) -> LevelingSlot? {
        var pass = shufflePass
        if row < queue.count {
            pass?.arrive(at: queue[row].id)
        }
        let next = playbackOrder.next(after: row, count: queue.count, pass: pass, row: queueRow(of:))
        return next.flatMap { $0 < queue.count ? levelingSlot(queue[$0].file) : nil }
    }

    func levelingSlot(_ file: AudioFile) -> LevelingSlot {
        LevelingSlot(url: file.absoluteURL, trackID: file.trackID, durationSeconds: file.durationSeconds)
    }

    // MARK: - The start

    /// The decision the start numbered `epoch` carries for `file`. A resume, a device move or a restart of the song
    /// playing carries the decision it plays with (the engine keeps that plan: B1). Another song: looked up first if
    /// the prefetch has not yet (`waitForStartLookup`, at most 50 ms), then decided between the song heard before it
    /// and the next. Kept as the song playing's only while the start is still the newest.
    func levelingDecisionForStart(of file: AudioFile, epoch: UInt64) async -> TrackLevelingDecision {
        let slot = levelingSlot(file)
        levelingState.armed = nil // a start begins a new playback: the engine drops the armed pick
        if let playing = levelingState.playing, playing.key == slot.key {
            return playing.decision
        }
        if !levelingState.knowledge.resolved.contains(slot.key), let sources = levelingSources {
            await waitForStartLookup(slot, sources: sources)
        }
        let previous = levelingState.playing?.key
        let next = selectedTrackIndex.flatMap { levelingSlot(after: $0) }
        let decision = levelingState.knowledge.library.decision(for: LevelingRequest(
            key: slot.key, mode: levelingMode, previous: previous, next: next?.key, atSeam: false
        ))
        if transportCommand == .start(epoch) {
            levelingState.play(.init(key: slot.key, decision: decision, atSeam: false, previous: previous))
        }
        logUX("leveling: start '\(file.name)' — \(Self.describe(decision))")
        return decision
    }

    /// Look `slot` up alone and wait for it at most `LevelingState.startWait`. A lookup still running then lands
    /// when it finishes, for the next request; the start goes on with what is known — never waiting for it (a race,
    /// not a task group: a group would wait for its slower child).
    private func waitForStartLookup(_ slot: LevelingSlot, sources: any LevelingSources) async {
        let previous = levelingState.knowledge
        let race = FirstOf()
        work.spawn { [self] in
            let found = await LevelingLoad(sources: sources, previous: previous).single(slot)
            levelingState.knowledge.merge(found)
            race.finish(true)
        }
        let clock = levelingState.clock
        let timer = Task { @MainActor in
            try? await clock.sleep(for: LevelingState.startWait)
            race.finish(false)
        }
        let landed = await race.value()
        timer.cancel()
        if !landed {
            logUX("leveling: '\(slot.url.lastPathComponent)' not looked up within 50 ms — it starts with what is known")
        }
    }

    // MARK: - The arm

    /// The decision the pick at `index` is armed with (`armOnDeck`; nil with no pick). It becomes audible at a seam
    /// after the song playing, so it is decided between that song — whose decision a continuous seam inherits —
    /// and the song after it. Synchronous: from what the prefetch knows.
    func levelingDecisionForArm(at index: Int?) -> TrackLevelingDecision? {
        promoteArmedPickIfItBecameAudible()
        guard let index, index < queue.count else {
            levelingState.armed = nil
            return nil
        }
        let sent = armedDecision(for: levelingSlot(queue[index].file), at: index)
        levelingState.armed = sent
        levelingState.armedAtTransition = lastTransitionCount
        return sent.decision
    }

    /// The pick `slot` at `index`, decided after the song playing.
    private func armedDecision(for slot: LevelingSlot, at index: Int) -> LevelingState.Sent {
        let playing = levelingState.playing
        let decision = levelingState.knowledge.library.decision(for: LevelingRequest(
            key: slot.key, mode: levelingMode, previous: playing?.key, next: levelingSlot(after: index)?.key,
            atSeam: true, previousDecision: playing?.decision
        ))
        return .init(key: slot.key, decision: decision, atSeam: true, previous: playing?.key)
    }

    /// A seam since the last arm made the armed pick the song playing: its decision is the one playing now.
    private func promoteArmedPickIfItBecameAudible() {
        guard let armed = levelingState.armed, lastTransitionCount != levelingState.armedAtTransition else { return }
        levelingState.play(armed)
        levelingState.armed = nil
    }

    /// The armed pick's analysis (or its album's) landed after it was armed: re-arm it with the new decision, so it
    /// takes effect at the next song — only while the song playing has more than `rearmMargin` left and no seam
    /// has gone by unseen, so the re-arm can never land after the seam it is for. On Enhanced only (Pure ignores
    /// leveling).
    func rearmIfTheArmedDecisionChanged() {
        promoteArmedPickIfItBecameAudible()
        guard let armed = levelingState.armed, let index = pendingNextIndex, index < queue.count,
              levelingSlot(queue[index].file).key == armed.key,
              isPlaying, transportCommand == nil, signalPath.path == .enhanced,
              duration - playbackPosition > Self.rearmMargin,
              engine.snapshot().transport.transitionCount == lastTransitionCount else { return }
        let fresh = armedDecision(for: levelingSlot(queue[index].file), at: index)
        guard fresh.decision != armed.decision else { return }
        logUX("leveling: the next song's decision changed (its analysis landed) — re-armed: "
            + Self.describe(fresh.decision))
        armOnDeck(index: index)
    }

    /// How much of the song playing must be left for a re-arm (seconds).
    static let rearmMargin = 5.0

    // MARK: - The listener's mode change

    /// Leveling changed from `old`: the song playing re-plans with the new mode at once — both units glide 0.15 s —
    /// and the armed pick's decision is replaced (N11). Nothing playing, or Pure playing: nothing to send (the next
    /// start decides with the new mode).
    func levelingChanged(from old: LevelingSetting) {
        guard leveling != old else { return }
        logUX("leveling → \(leveling.rawValue)")
        guard let playing = levelingState.playing, signalPath.path != .pure else { return }
        let library = levelingState.knowledge.library
        let previousDecision = playing.previous.map { previous in
            library.decision(for: LevelingRequest(key: previous, mode: levelingMode, next: playing.key))
        }
        let current = library.decision(for: LevelingRequest(
            key: playing.key, mode: levelingMode, previous: playing.previous,
            next: selectedTrackIndex.flatMap { levelingSlot(after: $0) }?.key,
            atSeam: playing.atSeam, previousDecision: playing.atSeam ? previousDecision : nil
        ))
        levelingState.play(.init(key: playing.key, decision: current, atSeam: playing.atSeam,
                                 previous: playing.previous))
        var next: TrackLevelingDecision?
        if let armed = levelingState.armed, let index = pendingNextIndex, index < queue.count,
           levelingSlot(queue[index].file).key == armed.key {
            let sent = armedDecision(for: levelingSlot(queue[index].file), at: index)
            levelingState.armed = sent
            next = sent.decision
        }
        engine.applyLevelingChange(current: current, next: next)
        refreshLevelingReadout() // paused, the tick sleeps
    }

    /// The song playing's plan as the engine made it, read now (the tick carries it while a song plays).
    func refreshLevelingReadout() {
        let readout = engine.snapshot().signalPath.leveling
        if signalPath.leveling != readout {
            signalPath.leveling = readout
        }
    }

    /// A decision in a few words, for the play log.
    static func describe(_ decision: TrackLevelingDecision) -> String {
        let loudness = decision.folded.map { $0.loudness.indices.contains($0.variant) ? $0.loudness[$0.variant] : .nan }
            ?? decision.unfolded.loudness
        return "\(decision.mode) from \(decision.source)"
            + (loudness.map { String(format: ", L %.2f LUFS", $0) } ?? ", L unknown")
            + (decision.folded.map { ", folded (LFE variant \($0.variant))" } ?? "")
            + (decision.continuousWithPrevious ? ", continuous" : "")
    }
}

/// The first of two outcomes, on the main actor: whoever finishes first answers, the other is ignored.
@MainActor
private final class FirstOf {
    private var answer: Bool?
    private var waiter: CheckedContinuation<Bool, Never>?

    func finish(_ value: Bool) {
        guard answer == nil else { return }
        answer = value
        waiter?.resume(returning: value)
        waiter = nil
    }

    func value() async -> Bool {
        if let answer {
            return answer
        }
        return await withCheckedContinuation { waiter = $0 }
    }
}
