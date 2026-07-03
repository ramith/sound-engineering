// ChecksMetadataPass — S8.3 Slice-4 case: the MetadataScanner background pass, driven
// with STUB extractors over SYNTHETIC tracks (no real files — full real-file extraction
// is Slice 5's M1/M2). Proves the pass orchestration: enrich pending tracks (tags +
// deduped art + album cover), mark them, idempotent re-run (0 extractions), and the
// tagless anti-loop. Same VerifyAUGraph idiom.

import CoreGraphics
import Dispatch
import Foundation
import LibraryScan
import LibraryStore

/// Fixed non-image art bytes shared by every stubbed track (so they dedup to ONE artwork
/// row). Not a valid image — ArtworkCache still caches the original + hashes it (no thumb).
private let stubArtBytes = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])

/// A canned extractor: either full tags (+ optional art) or an empty (tagless) result.
private struct StubExtractor: MetadataExtracting {
    let withArt: Bool
    let emptyTags: Bool
    func extract(from _: URL) async -> ExtractedMetadata? {
        let meta = emptyTags
            ? TrackMetadata()
            : TrackMetadata(title: "Stub Title", artistName: "Stub Artist", albumTitle: "Stub Album")
        let art = withArt ? ExtractedArtwork(data: stubArtBytes, uti: nil) : nil
        return ExtractedMetadata(metadata: meta, artwork: art)
    }
}

/// Counts extract() calls (thread-safe via an actor) so idempotency can assert 0 re-extractions.
private actor CallCounter {
    private var value = 0
    func bump() {
        value += 1
    }

    func count() -> Int {
        value
    }
}

private struct CountingStub: MetadataExtracting {
    let counter: CallCounter
    func extract(from _: URL) async -> ExtractedMetadata? {
        await counter.bump()
        return ExtractedMetadata(metadata: TrackMetadata(title: "Counted"), artwork: nil)
    }
}

// MARK: - x — MetadataScanner pass (enrich + idempotency + tagless anti-loop)

func checkMetadataPass(number: Int, url: URL) async -> Bool {
    let cacheDir = url.deletingLastPathComponent()
        .appendingPathComponent("meta-cache-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: cacheDir) }
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let cache = ArtworkCache(directory: cacheDir)
        let root = try await store.addRoot(URL(fileURLWithPath: "/Music/Pass"))
        let gen = try await store.beginScanGeneration()
        let ids = try await store.upsert(
            (0 ..< 5).map { makeScanned(path: "/Music/Pass/t\($0).flac", name: "t\($0)") },
            folderID: root, generation: gen
        )
        guard ids.count == 5 else { printFail(number, "pass: 5-track seed failed"); return false }

        // Pass 1: enrich all with the stub (title + a shared cover).
        try await MetadataScanner().run(
            generation: gen, into: store, cache: cache, extractor: StubExtractor(withArt: true, emptyTags: false)
        )
        for id in ids {
            guard let row = try await store.track(id: id), row.title == "Stub Title", row.artworkKey != nil else {
                printFail(number, "pass: track \(id) was not enriched"); return false
            }
        }
        guard try await store.tracksNeedingMetadata(limit: 100).isEmpty else {
            printFail(number, "pass: tracks still need metadata after the pass"); return false
        }
        guard try await store.countRows(inTable: "artwork") == 1 else {
            printFail(number, "pass: shared art did not dedup to one row"); return false
        }

        // Idempotency: a re-run extracts NOTHING (all already marked).
        let counter = CallCounter()
        try await MetadataScanner().run(
            generation: gen, into: store, cache: cache, extractor: CountingStub(counter: counter)
        )
        guard await counter.count() == 0 else {
            printFail(number, "pass: re-run extracted \(await counter.count()) (expected 0 — idempotent)")
            return false
        }
        return await checkPassNoTagsAntiLoop(store, cache: cache, root: root, number: number)
    } catch {
        printFail(number, "metadata pass threw: \(error)"); return false
    }
}

/// A tagless file is MARKED (so it never re-extracts) even though it gets no title — the
/// anti-loop guarantee; a second pass then finds nothing to do.
private func checkPassNoTagsAntiLoop(
    _ store: LibraryStore, cache: ArtworkCache, root: Int64, number: Int
) async -> Bool {
    do {
        let gen = try await store.beginScanGeneration()
        let ids = try await store.upsert(
            [makeScanned(path: "/Music/Pass/notags.flac", name: "notags")], folderID: root, generation: gen
        )
        guard let trackID = ids.first else { printFail(number, "no-tags: seed failed"); return false }
        try await MetadataScanner().run(
            generation: gen, into: store, cache: cache, extractor: StubExtractor(withArt: false, emptyTags: true)
        )
        guard try await store.track(id: trackID)?.title == nil,
              try await store.tracksNeedingMetadata(limit: 100).isEmpty else {
            printFail(number, "no-tags: tagless track not marked (would re-extract forever)"); return false
        }
        let counter = CallCounter()
        try await MetadataScanner().run(
            generation: gen, into: store, cache: cache, extractor: CountingStub(counter: counter)
        )
        guard await counter.count() == 0 else {
            printFail(number, "no-tags: second pass re-extracted the tagless file (\(await counter.count()))")
            return false
        }
        printPass(number, "MetadataScanner pass: enriches pending tracks (tags + deduped art + album cover) "
            + "and marks them (idempotent re-run extracts 0); a tagless file is marked and NEVER "
            + "re-extracted (anti-loop)")
        return true
    } catch {
        printFail(number, "no-tags anti-loop threw: \(error)"); return false
    }
}

// MARK: - metadata-pass cancellation skips the orphan sweep (M9, design §6 / §11-f)

/// A pass cancelled mid-flight MUST commit its already-applied rows but SKIP the end-of-pass
/// artwork orphan sweep — otherwise a cancelled pass on a partial view could delete cache
/// files a not-yet-processed track will reference. The scan pass proves this (case M); this
/// is the distinct `MetadataScanner` path. Idiom mirrors ChecksScanEdge's parked rendezvous.
func checkMetadataPassCancellation(number: Int, url: URL) async -> Bool {
    let cacheDir = url.deletingLastPathComponent()
        .appendingPathComponent("m9-cache-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: cacheDir) }
    do {
        let store = try await LibraryStore(url: url, appBuild: "verify")
        let cache = ArtworkCache(directory: cacheDir)
        let root = try await store.addRoot(URL(fileURLWithPath: "/Music/M9"))
        let gen = try await store.beginScanGeneration()
        let ids = try await store.upsert(
            (0 ..< 4).map { makeScanned(path: "/Music/M9/t\($0).flac", name: "t\($0)") },
            folderID: root, generation: gen
        )
        guard ids.count == 4 else { printFail(number, "m9: 4-track seed failed"); return false }
        // Seed an ORPHAN artwork row referenced by no track/album — a COMPLETED pass would sweep it.
        try await store.linkArtwork(contentHash: "m9orphan", cachePath: "/cache/m9orphan.jpg", size: .zero, byteSize: 0)
        guard try await store.countRows(inTable: "artwork") == 1 else {
            printFail(number, "m9: orphan seed failed"); return false
        }
        // Park after the first apply, cancel, release → the pass must throw and skip the sweep.
        guard try await cancelPassAfterFirstApply(store, cache: cache, gen: gen, number: number) else { return false }
        // Sweep skipped ⇒ the orphan SURVIVES (artwork = {m9orphan, t0's shared art} = 2), and t0
        // was enriched + marked (< 4 still pending).
        guard try await store.countRows(inTable: "artwork") == 2 else {
            printFail(number, "m9: orphan was swept despite cancellation (sweep NOT skipped)"); return false
        }
        guard try await store.tracksNeedingMetadata(limit: 10).count < 4 else {
            printFail(number, "m9: no track was enriched before cancel (rendezvous mis-timed)"); return false
        }
        // A full (uncancelled) pass now completes and DOES sweep the orphan.
        try await MetadataScanner().run(
            generation: gen, into: store, cache: cache, extractor: StubExtractor(withArt: true, emptyTags: false)
        )
        guard try await store.countRows(inTable: "artwork") == 1 else {
            printFail(number, "m9: a full pass did not sweep the orphan"); return false
        }
        printPass(number, "metadata-pass cancellation skips the sweep (§6/§11-f): a pass cancelled after the "
            + "first apply throws CancellationError, keeps its applied+marked row, and does NOT sweep — a "
            + "pre-seeded orphan SURVIVES; a later full pass reaps it")
        return true
    } catch {
        printFail(number, "m9 cancellation threw: \(error)"); return false
    }
}

/// Run the pass, park it in its progress closure after the FIRST apply, cancel while parked,
/// then release so the drain loop's next `checkCancellation()` throws. Returns true iff the
/// pass threw `CancellationError`. Mirrors ChecksScanEdge.cancelAfterFirstBatch exactly.
private func cancelPassAfterFirstApply(
    _ store: LibraryStore, cache: ArtworkCache, gen: Int64, number: Int
) async throws -> Bool {
    let firstApply = OneShotLatch()
    let proceed = DispatchSemaphore(value: 0) // released after cancel; wait()ed in the SYNC closure only
    let applied = AsyncStream<Void>.makeStream()
    let task = Task {
        try await MetadataScanner().run(
            generation: gen, into: store, cache: cache,
            extractor: StubExtractor(withArt: true, emptyTags: false),
            progress: { _ in
                firstApply.runOnce {
                    applied.continuation.yield(())
                    applied.continuation.finish()
                    proceed.wait() // park the pass after the first apply until the test has cancelled
                }
            }
        )
    }
    var applies = applied.stream.makeAsyncIterator()
    _ = await applies.next() // await the first applied row (no async-context semaphore wait)
    task.cancel()
    proceed.signal() // release → the drain loop's next checkCancellation() throws
    do {
        try await task.value
        printFail(number, "m9: cancelled pass did NOT throw"); return false
    } catch is CancellationError {
        return true
    } catch {
        printFail(number, "m9: pass threw \(error), expected CancellationError"); return false
    }
}
