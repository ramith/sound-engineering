import Foundation
import LibraryScan
import LibraryStore

// MARK: - LibraryModel metadata-pass seam (S8.3 — was AudioViewModel+LibraryMetadata)

//
// The enrichment half, chained after `performScan` (design §6): once the structural scan
// has upserted rows, this fills tags + cover art for the ones that still need it (and, at
// launch, `resumePendingMetadata` runs it alone for songs left pending — S10.8 C2). Mirrors
// the scan seam — `runMetadataPass` is `@MainActor` (extension inheritance) and only
// publishes `metadataProgress` there; the heavy per-file extraction + thumbnailing run OFF
// the main actor inside `MetadataScanner`'s bounded task group, and store WRITES serialize
// on the actor. Only `Sendable` types cross. The pass ENDS with the album regroup + orphan
// facet and artwork sweeps, so `libraryRevision` bumps after the library is consistent.
// Cancellation (a re-trigger/teardown cancelling `scanTask`) makes the pass throw and SKIP them.

extension LibraryModel {
    /// Run the metadata pass over the store's pending-metadata tracks — all of them, or one
    /// root's (`folderID`, a live reconcile) — reusing the scan's `generation`. No-op if the
    /// artwork cache never built (store construction failed).
    func runMetadataPass(_ store: LibraryStore, generation: Int64, inFolder folderID: Int64? = nil) async {
        guard let cache = metadataArtworkCache else { return }
        logUX("runMetadataPass: start (generation \(generation))")
        do {
            try await MetadataScanner().run(
                generation: generation, into: store, cache: cache, extractor: MetadataExtractor(),
                inFolder: folderID,
                progress: { snapshot in
                    Task { @MainActor [weak self] in self?.metadataProgress = snapshot }
                }
            )
            metadataProgress = nil
            // Album/artist rows + artwork links now exist — signal the browse layer to reload
            // its facets (review B1). Once per completed pass (scan or reconcile both land here).
            libraryRevision &+= 1
            logUX("runMetadataPass: done (generation \(generation))")
        } catch is CancellationError {
            metadataProgress = nil // expected on a re-trigger/teardown; enriched rows stay valid
            logUX("runMetadataPass: cancelled (generation \(generation); enriched rows remain valid)")
        } catch {
            metadataProgress = nil
            // Log the FULL error (not just localizedDescription, which drops the cause): a store
            // failure — e.g. a schema-drift `no such column: metadata_scanned` on a DB created by
            // a pre-S8.3 build — surfaces HERE, in Console, instead of vanishing into the banner.
            logUX("runMetadataPass: FAILED — \(error)")
            onError?("Metadata pass failed: \(error.localizedDescription)")
        }
    }
}
