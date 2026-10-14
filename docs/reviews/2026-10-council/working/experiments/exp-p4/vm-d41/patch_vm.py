# Apply the D41 design's VM side (d41-design.md §2.3 M1/M2, §3) to the COPIED sources in .out/src.
import sys, os
src = sys.argv[1]
def edit(name, pairs):
    p = os.path.join(src, name)
    s = open(p).read()
    for old, new in pairs:
        if old not in s:
            sys.exit(f"patch anchor missing in {name}: {old[:60]!r}")
        s = s.replace(old, new)
    open(p, "w").write(s)

edit("AudioPlaybackEngine.swift", [
    ("    func setNextTrack(_: URL?) async {}", "    func setNextTrack(_: URL?, ticket _: OnDeckTicket) async {}"),
    ("    func setNextTrack(_ fileURL: URL?) async\n", "    func setNextTrack(_ fileURL: URL?, ticket: OnDeckTicket) async\n"),
])
edit("AudioViewModel.swift", [
    ("    @ObservationIgnored var transportStopEpoch: UInt64 = 0",
     "    @ObservationIgnored var transportStopEpoch: UInt64 = 0\n"
     "    /// D41 design M2: the epoch of the newest startPlayback; on-deck tickets name it.\n"
     "    @ObservationIgnored var onDeckSession: UInt64 = 0\n"
     "    /// D41 design: VM request order, never reset.\n"
     "    @ObservationIgnored var onDeckSequence: UInt64 = 0\n"
     "    func nextOnDeckTicket() -> OnDeckTicket {\n"
     "        onDeckSequence += 1\n"
     "        return OnDeckTicket(session: onDeckSession, sequence: onDeckSequence)\n"
     "    }"),
])
edit("AudioViewModel+Queue.swift", [
    ("""    func armOnDeck(index: Int?) {
        pendingNextIndex = index
        let url: URL? = index.flatMap { $0 >= 0 && $0 < queue.count ? queue[$0].file.absoluteURL : nil }
        Task { [weak self] in
            guard let self else { return }
            await engine.setNextTrack(url)
        }
    }""",
     """    @discardableResult
    func armOnDeck(index: Int?) -> Task<Void, Never> {
        pendingNextIndex = index
        let url: URL? = index.flatMap { $0 >= 0 && $0 < queue.count ? queue[$0].file.absoluteURL : nil }
        let ticket = nextOnDeckTicket() // M1: pending, URL and ticket in one main-actor turn
        return Task { [weak self] in
            guard let self else { return }
            await engine.setNextTrack(url, ticket: ticket)
        }
    }"""),
])
edit("AudioViewModel+Playback.swift", [
    ("        let epoch = nextTransportEpoch()\n\n        Task {",
     "        let epoch = nextTransportEpoch()\n        onDeckSession = epoch // M2\n\n        Task {"),
    ("                guard transportStopEpoch < epoch else { return }\n                await primeGaplessPipeline",
     "                guard transportStopEpoch < epoch else { return }\n                guard onDeckSession == epoch else { return } // M2: a superseded start does not prime\n                await primeGaplessPipeline"),
    ("""        let nextIdx = computeNextIndex(current: currentIdx ?? 0, playlistCount: playlist.count)
        pendingNextIndex = nextIdx

        if let idx = nextIdx, idx < playlist.count {
            let nextURL = playlist[idx].absoluteURL
            await engine.setNextTrack(nextURL)
            logUX("startPlayback: primed next index=\\(idx) pureMode=\\(pureMode)")
        } else {
            await engine.setNextTrack(nil)
            logUX("startPlayback: no next track to prime (single-track or end of playlist)")
        }""",
     """        let nextIdx = computeNextIndex(current: currentIdx ?? 0, playlistCount: playlist.count)
        await armOnDeck(index: nextIdx.flatMap { $0 < playlist.count ? $0 : nil }).value
        logUX("startPlayback: primed next index=\\(String(describing: nextIdx)) pureMode=\\(pureMode)")"""),
])
edit("AudioViewModel+AutoAdvance.swift", [
    ("""        Task { [weak self] in
            guard let self else { return }
            if let newIdx = newNextIdx, newIdx < playlist.count {
                let nextURL = playlist[newIdx].absoluteURL
                await engine.setNextTrack(nextURL)
                logUX("trackTransition: primed next index=\\(newIdx) pureMode=\\(pureModeSnap)")
            } else {
                await engine.setNextTrack(nil)
                logUX("trackTransition: no further track to queue")
            }
        }""",
     """        _ = pureModeSnap
        armOnDeck(index: newNextIdx.flatMap { $0 < playlist.count ? $0 : nil })"""),
])
edit("AudioViewModel+Playlist.swift", [
    ("""            pendingNextIndex = newNextIdx
            Task { [weak self] in
                guard let self else { return }
                if let newIdx = newNextIdx, newIdx < queue.count {
                    await engine.setNextTrack(queue[newIdx].file.absoluteURL)
                } else {
                    await engine.setNextTrack(nil)
                }
            }""",
     """            armOnDeck(index: newNextIdx.flatMap { $0 < queue.count ? $0 : nil })"""),
])
edit("AudioViewModel+SpectrumTimer.swift", [
    ("""            pendingNextIndex = nil
            Task { await engine.setNextTrack(nil) }""",
     """            armOnDeck(index: nil)"""),
])
edit("AudioViewModel+Lifecycle.swift", [
    ("""            let epoch = nextStopEpoch()
            await engine.setNextTrack(nil)
            try await engine.stopAudio(epoch: epoch)
            isPlaying = false
        } catch {
            errorMessage = "Pause failed""",
     """            let epoch = nextStopEpoch()
            await engine.setNextTrack(nil, ticket: nextOnDeckTicket())
            try await engine.stopAudio(epoch: epoch)
            isPlaying = false
        } catch {
            errorMessage = "Pause failed"""),
    ("""            let epoch = nextStopEpoch()
            await engine.setNextTrack(nil)
            try await engine.stopAudio(epoch: epoch)
            isPlaying = false
            playbackPosition = 0""",
     """            let epoch = nextStopEpoch()
            await engine.setNextTrack(nil, ticket: nextOnDeckTicket())
            try await engine.stopAudio(epoch: epoch)
            isPlaying = false
            playbackPosition = 0"""),
])
print("design VM patch applied")
