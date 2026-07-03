// MetadataScanner — the S8.3 background metadata pass (design §6).
//
// Enriches tracks that still need metadata (metadata_scanned == 0). Extraction (file
// read + parse + thumbnail) is CPU/IO-bound and runs OFF the actor in bounded-concurrency
// chunks; the store WRITES serialize on the actor (one applyExtractedResult transaction
// per track). Triggered after the structural scan (NOT inline), reusing the scan's
// generation. FS-tolerant (a vanished file → extract nil → still marked, anti-loop),
// cancellable (per-chunk + per-file checkCancellation; a cancelled pass SKIPS the
// end-of-pass artwork orphan sweep — no wrongful file delete on a partial view).

import Foundation
import LibraryStore

public struct MetadataScanner: Sendable {
    /// A per-track extraction result crossing back from the concurrent group (Sendable).
    private struct ChunkResult {
        let trackID: Int64
        let metadata: TrackMetadata?
        let artwork: ArtworkLink?
    }

    public init() {}

    /// Run the pass to completion (or until cancelled). Pulls the pending-metadata id
    /// snapshot, enriches each in bounded-concurrency chunks, then sweeps orphaned artwork.
    public func run(
        generation: Int64, into store: LibraryStore, cache: ArtworkCache,
        extractor: some MetadataExtracting,
        progress: (@Sendable (MetadataProgress) -> Void)? = nil
    ) async throws {
        let pending = try await store.tracksNeedingMetadata(limit: Int(Int32.max))
        let total = pending.count
        guard total > 0 else { return }
        // Chunk = the concurrency cap: each chunk's tracks extract fully concurrently, then
        // apply serially. Bounds off-actor work to the M1→M5 core profile (each child does
        // ImageIO + file I/O, so cap modestly to avoid thrashing a 4-core machine).
        let chunkSize = max(1, min(ProcessInfo.processInfo.activeProcessorCount, 6))
        var processed = 0
        var index = 0
        while index < pending.count {
            try Task.checkCancellation()
            let upper = min(index + chunkSize, pending.count)
            let chunk = Array(pending[index ..< upper])
            index = upper
            for result in try await extractChunk(chunk, store: store, cache: cache, extractor: extractor) {
                try await apply(result, into: store, generation: generation)
                processed += 1
                progress?(MetadataProgress(filesProcessedSoFar: processed, totalToProcess: total))
            }
        }
        // Reached ONLY on clean completion (a cancelled pass threw above): reap artwork rows
        // no track/album references any more, and delete their cache files.
        for orphan in try await store.sweepOrphanArtwork() {
            cache.removeFiles(forContentHash: orphan.contentHash, cachePath: orphan.cachePath)
        }
    }

    /// Apply one result on the actor: tags+art in one transaction, or just the anti-loop
    /// marker for a vanished/unreadable file (extract returned nil).
    private func apply(_ result: ChunkResult, into store: LibraryStore, generation: Int64) async throws {
        if let metadata = result.metadata {
            try await store.applyExtractedResult(
                trackID: result.trackID, meta: metadata, artwork: result.artwork, generation: generation
            )
        } else {
            try await store.markMetadataScanned(trackID: result.trackID, generation: generation)
        }
    }

    /// Resolve the chunk's urls (on the actor), then extract + cache art CONCURRENTLY off
    /// the actor. Only Sendable results cross back. A row deleted since the snapshot is
    /// silently dropped (it won't reappear in `tracksNeedingMetadata`).
    private func extractChunk(
        _ ids: [Int64], store: LibraryStore, cache: ArtworkCache, extractor: some MetadataExtracting
    ) async throws -> [ChunkResult] {
        var jobs: [(id: Int64, url: URL)] = []
        for id in ids {
            if let track = try await store.track(id: id) { jobs.append((id, track.url)) }
        }
        return try await withThrowingTaskGroup(of: ChunkResult.self) { group in
            for job in jobs {
                group.addTask {
                    try Task.checkCancellation()
                    guard let extracted = await extractor.extract(from: job.url) else {
                        return ChunkResult(trackID: job.id, metadata: nil, artwork: nil)
                    }
                    var link: ArtworkLink?
                    if let art = extracted.artwork {
                        link = try? cache.store(imageData: art.data, uti: art.uti)
                    }
                    return ChunkResult(trackID: job.id, metadata: extracted.metadata, artwork: link)
                }
            }
            var results: [ChunkResult] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
    }
}
