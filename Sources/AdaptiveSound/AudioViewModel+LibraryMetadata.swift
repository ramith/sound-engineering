import Foundation
import LibraryScan
import LibraryStore

// MARK: - AudioViewModel metadata-pass seam (S8.3 — ADDITIVE)

//
// The enrichment half, chained after `performScan` (design §6): once the structural scan
// has upserted rows, this fills tags + cover art for the ones that still need it. Mirrors
// the scan seam — `runMetadataPass` is `@MainActor` (extension inheritance) and only
// publishes `metadataProgress` there; the heavy per-file extraction + thumbnailing run OFF
// the main actor inside `MetadataScanner`'s bounded task group, and store WRITES serialize
// on the actor. Only `Sendable` types cross. Cancellation (a re-trigger/teardown cancelling
// `scanTask`) makes the pass throw and SKIP its end-of-pass artwork orphan sweep.

extension AudioViewModel {
    /// Run the metadata pass over the store's pending-metadata tracks, reusing the scan's
    /// `generation`. No-op if the artwork cache never built (store construction failed).
    func runMetadataPass(_ store: LibraryStore, generation: Int64) async {
        guard let cache = metadataArtworkCache else { return }
        logUX("runMetadataPass: start (generation \(generation))")
        do {
            try await MetadataScanner().run(
                generation: generation, into: store, cache: cache, extractor: MetadataExtractor(),
                progress: { snapshot in
                    Task { @MainActor [weak self] in self?.metadataProgress = snapshot }
                }
            )
            metadataProgress = nil
            logUX("runMetadataPass: done (generation \(generation))")
        } catch is CancellationError {
            metadataProgress = nil // expected on a re-trigger/teardown; enriched rows stay valid
            logUX("runMetadataPass: cancelled (generation \(generation); enriched rows remain valid)")
        } catch {
            metadataProgress = nil
            // Log the FULL error (not just localizedDescription, which drops the cause): a store
            // failure — e.g. a schema-drift `no such column: metadata_scanned` on a DB created by
            // a pre-S8.3 build — surfaces HERE, in Console, instead of vanishing into errorMessage.
            logUX("runMetadataPass: FAILED — \(error)")
            errorMessage = "Metadata pass failed: \(error.localizedDescription)"
        }
    }
}
