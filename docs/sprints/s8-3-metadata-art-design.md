# S8.3 — Metadata + Embedded-Art Extraction (design)

Status: **VETTED — architect GO-WITH-CHANGES (all applied), implementation-ready.** Chunk S8.3 of the S8 library spine, branch
`feat/sprint-5-eq-wiring` (Swift 6 language mode, `.macOS(.v26)`, strict concurrency = errors).
Synthesized from two design fan-outs (extractor; cache/pass/tests) + grounding.

## 0. Scope & what already exists

S8.3 = read embedded tags + cover art from **local** files and populate the store. It is
the enrichment sequel to the S8.2 structural scan.

**The store WRITE side already exists** (S8.1b) — do NOT rebuild it:
- `TrackMetadata` (`LibraryTypes.swift:253`) — the Sendable write payload.
- `applyMetadata(_:forTrack:)` (`LibraryStore+Facets.swift:120`) — resolves album/artist/genre in one txn, idempotent.
- `resolveArtist/Album/Genre` (`+Facets.swift:162-230`) — race-safe (`ON CONFLICT DO NOTHING` + re-SELECT).
- `linkArtwork(contentHash:cachePath:size:byteSize:)` (`+Facets.swift:132`) — UPSERTs an `artwork` row at `ref_count = 0`; its doc explicitly hands **extraction + on-disk cache + ref_count maintenance to S8.3**.
- Schema: `artwork(content_hash PK, cache_path, width, height, byte_size, ref_count)`; `tracks`/`albums` `.artwork_key → artwork ON DELETE SET NULL`; `tracks` metadata columns all NULL until now.

**S8.3 therefore builds:** MetadataExtractor · a thin FFmpeg-metadata C bridge · ArtworkCache (+ thumbnail) · ref_count/orphan ops · an idempotency marker · the MetadataScanner background pass · the VM seam · tests.

## 1. Locked founder decisions (do not relitigate)
1. **Extraction = AVFoundation PRIMARY + FFmpeg FALLBACK** (mirrors the decode path). Apple handles mp3/m4a/aac/alac/aiff/wav; FFmpeg fills FLAC + Ogg (and any file Apple returns empty for). FFmpeg-absent ⇒ graceful degradation (those files carry partial/no tags but still exist as rows).
2. **Separate BACKGROUND pass** after the structural scan — NOT inline in the walk.
3. **Artwork = cache original + generate a thumbnail now** (~512 px, ImageIO).
4. **Local only** — no online lookup; **no metadata-provenance marker** (both deferred to a future enrichment epic).

## 2. MetadataExtractor (produces data; never touches the store)

New `Sources/LibraryScan/MetadataExtractor.swift` (peer to `LibraryScanner`; shares `supportedExtensions` at `LibraryScanner.swift:39`). A stateless `Sendable` struct → concurrent calls are race-free.

```swift
public struct ExtractedArtwork: Sendable, Equatable { let data: Data; let uti: String? }
public struct ExtractedMetadata: Sendable, Equatable { let metadata: TrackMetadata; let artwork: ExtractedArtwork? }

public protocol MetadataExtracting: Sendable {              // seam for test injection (see §10)
    func extract(from url: URL) async -> ExtractedMetadata?
}
public struct MetadataExtractor: MetadataExtracting { public init() {} /* … */ }
```

- `async`, **non-throwing, Optional** — every failure is "skip/partial", never caller-actionable (mirrors `makeScannedFile` returning nil, `LibraryScanner.swift:160`). `nil` is reserved for **unreadable/vanished only**; a readable-but-tagless file returns a `TrackMetadata` carrying just duration/format.
- Swift-6: AVFoundation reads are `async load(...)`; nothing non-`Sendable` (`AVAsset`, `CGImage`) escapes the function.

**AVFoundation path** (mp3/m4a/aac/alac/aiff/wav): `asset.load(.metadata)` + `.id3Metadata`/`.iTunesMetadata` spaces; `load(.duration)` → `durationMs = Int64((seconds*1000).rounded())`; audio-track `formatDescriptions` → ASBD `mSampleRate`/`mChannelsPerFrame`/`mBitsPerChannel` (0 ⇒ `bitDepth = nil`); artwork via `commonKeyArtwork`/`APIC`/`covr` `dataValue`.

**Key → field precedence: common → iTunes → ID3** (defensive number parsing; unparseable → nil; `TRCK`/`TPOS` `"3/12"` split on `/`; empty-after-trim → nil). Full mapping table lives in the extractor's doc comment (title/artist/album/albumArtist/year/trackNo/discNo/genres/art). Vorbis-comment keys for the FFmpeg path: `title/artist/album/albumartist/date/tracknumber/discnumber/genre`.

**Trigger (extension-routed + cross-fill):**
- `flac`, `ogg` → **FFmpeg first**; if FFmpeg absent, best-effort AVFoundation (may still recover duration/format).
- others → **AVFoundation first**; if the core fields (title AND artist AND album all nil) came back empty **and** FFmpeg is available, do a cross-fill FFmpeg pass and merge (AVFoundation wins per-field, FFmpeg fills gaps). Keeps the common case a single read.
- Duration/format: prefer whichever path yields non-zero/non-nil (AVFoundation authoritative when both ran). Art: first path with non-empty bytes.

**Edge cases:** vanished mid-pass → nil; corrupt tags → partial; **embedded-art cap 32 MB** (above → drop art, protects pass memory); missing audio track → format nil, tags may still read; indefinite duration → 0 (schema "unknown"); undecodable-art UTI → `uti = nil` (cache still hashes bytes).

## 3. FFmpeg metadata bridge (reuse the existing dlopen backend — no new machinery)

- New **pure-C11 header** `Sources/AudioDSP/include/MetadataBridge.h` (POD structs + `extern "C"`, mirroring `PureModeBridge.h`), **`#include`d from `DeviceBridge.h`** (the module map exposes ONLY `DeviceBridge.h` — `module.modulemap:12`, same mechanism as `pureModeEvaluate`).
- Implementation in `FileDecodeSource.mm` behind the existing `#if __has_include(<libavformat/avformat.h>)` gate (`:44-61`), reusing the resolved `ffmpegApi()` singleton (`:437`). Add `av_dict_get`/`av_dict_count` to the `FFmpegApi` struct (`:310`) + resolve chain (`:382`). It opens its OWN short-lived `AVFormatContext` (open → find_stream_info → read `format->metadata` ∪ audio-stream metadata → copy `attached_pic` → read `codecpar` scalars → close); it does **not** touch the decode thread/ring.
- **C-ABI, callee-owned-buffer + explicit-free** (a NEW ownership contract — NOT the existing opaque-handle idiom; see §11-e for the `noexcept`/`malloc`/idempotent-free invariants): `int ffmpegReadMetadata(const char* path, CFileMetadata* out)` + `void ffmpegMetadataFree(CFileMetadata* out)`. `CFileMetadata` carries `available` flag, malloc'd `CMetaTag[]` (lowercased key/value), `artData`/`artLen`/`artMime`, `durationSeconds`, `sampleRate`/`channels`/`bitsPerRawSample`. Swift copies out under a `defer { ffmpegMetadataFree }` — one alloc site, one free site, no pointer escapes into a Sendable value. `available == 0` (FFmpeg absent / open failure / no file) ⇒ nothing allocated ⇒ free is a no-op ⇒ extractor degrades to AVFoundation-only.

## 4. ArtworkCache (+ thumbnail)

New `Sources/LibraryScan/ArtworkCache.swift`. CryptoKit + ImageIO + CoreGraphics (all system frameworks — zero new SwiftPM dep).

- **Location:** add `LibraryStore.defaultArtworkCacheURL()` beside `defaultStoreURL()` (`LibraryStore.swift:63`) → `~/Library/Application Support/AdaptiveSound/artwork/`. The VM passes the resolved dir in (tests/harness pass a `test-data/` temp dir — never real App Support).
- **Hash:** `SHA256` (lowercase-hex) over the **original embedded bytes** (deterministic dedup key = `artwork.content_hash` PK), independent of ImageIO re-encode nondeterminism.
- **On-disk convention (NO schema change):** `<hash>.<ext>` original (ext from source UTI, fallback `.img`) + `<hash>.thumb.jpg` thumbnail. `artwork.cache_path` stores the original; the thumb path is a pure function `ArtworkCache.thumbnailPath(forOriginal:)`, so S9 derives it. Dedup: `fileExists` on the original → skip re-writes.
- **Thumbnail:** ImageIO `CGImageSourceCreateThumbnailAtIndex`, **512 px max edge**, aspect-preserving, EXIF-orientation honored, JPEG q≈0.82. Undecodable art → write original, **skip thumb, don't throw** (best-effort, TOCTOU discipline).

```swift
public struct ArtworkRef: Sendable, Equatable { let contentHash: String; let cachePath: String; let pixelSize: CGSize; let byteSize: Int64 }
public struct ArtworkCache: Sendable {
    public init(directory: URL)
    public func store(imageData: Data) throws -> ArtworkRef
    public static func thumbnailPath(forOriginal cachePath: String) -> String
    public func removeFiles(forContentHash: String, cachePath: String)
}
```

## 5. Idempotency — `metadata_scanned` marker (RECOMMENDED)

The pass must (a) extract only tracks that need it and (b) be a no-op on re-run, **including a genuinely tagless file (must not re-extract forever).**

- Options weighed: drive-off-`ScanResult.trackIDs` (ephemeral, can't survive relaunch, returns *all* walked ids); metadata-NULL query (a no-tags file re-extracts forever — **fails the anti-loop requirement**); **a marker column (chosen)** — records *attempt*, decoupled from *outcome*.
- **Schema delta (v1-direct, mirroring how `dev`/`inode` were added — `Schema.swift:44-46`,`:98-100`; no populated production store, no migration):**
  `metadata_scanned INTEGER NOT NULL DEFAULT 0` on `tracks` (stores the **scan generation** attempted at, reusing `beginScanGeneration()` — composes with re-scan) + `CREATE INDEX idx_tracks_meta_scanned ON tracks(metadata_scanned)`.
- **`upsertOne` conflict SET resets `metadata_scanned = 0` ONLY on the *modified* branch** (`+DAO.swift:292` no-bump predicate), so a retagged file re-extracts; an unchanged upsert leaves it (idempotency preserved).
- DAO: `tracksNeedingMetadata(limit:) -> [Int64]` (`metadata_scanned == 0`, FS-independent) + `markMetadataScanned(trackID:generation:)`. Every attempt — success, no-tags, or vanished — ends with `markMetadataScanned` ⇒ re-run finds an empty set ⇒ true no-op.

## 6. MetadataScanner (the background pass)

New `Sources/LibraryScan/MetadataScanner.swift` + `MetadataProgress` (mirrors `ScanProgress.swift:15`; scalars only; **determinate** — starts from a known id list so `totalToProcess` is populated).

**Concurrency (Swift-6):** extraction is CPU/IO-bound + parallelizable; store writes serialize on the actor.
- Driver pulls a batch (~64) via `tracksNeedingMetadata(limit:)`.
- `withThrowingTaskGroup`, bounded to `min(activeProcessorCount, 6)` (each child does ImageIO + file I/O — don't thrash a 4-core M1): each child `try Task.checkCancellation()`, resolves the track `url`, runs the extractor **and** `ArtworkCache.store` (hashing/ImageIO/file-write all off-actor), returns a Sendable `(trackID, TrackMetadata, ArtworkRef?)`.
- Driver applies results **serially on the actor, ONE transaction per track** via a new `applyExtractedResult(trackID:meta:artwork:generation:)` that folds `applyMetadata` + (if art) `linkArtwork` + `attachArtwork` + `markMetadataScanned` into a SINGLE `connection.transaction` (VET SHOULD-FIX): "attempt recorded" then commits ATOMICALLY with the write, so an interrupt between them can't leave a written-but-unmarked row (which would needlessly re-extract next pass). Also halves actor hops per track (helps the S9-read-starvation goal, per the `batchSize=256` rationale, `LibraryScanner.swift:44`).
- **No-tags** → still `markMetadataScanned` (anti-loop). **Vanished** → mark scanned, no crash (diverged row legal; reads don't assert existence). **Cancellation** → applied rows valid + marked; **orphan-sweep runs ONLY on non-cancelled completion** (no wrongful file delete on a partial view).
- **Trigger:** at the tail of `performScan` (`AudioViewModel+LibraryScan.swift:67`), on the SAME `Task(priority:.utility)`, reusing the scan's `generation`. Driven by the store query (not `result.trackIDs`), so it also finishes any prior interrupted pass.

```swift
public func run(generation: Int64, into store: LibraryStore, cache: ArtworkCache,
                extractor: some MetadataExtracting,
                progress: (@Sendable (MetadataProgress) -> Void)? = nil) async throws
```

## 7. Orphan cleanup — pure reachability (no incremental counter)

**VET-resolved (§11-c): drop the incremental `ref_count` counter; orphan-sweep purely by reachability.** The `delete`/`sweepOrphans`/`removeRoot` paths null `artwork_key` via the FK without touching a counter, so an incrementally-maintained integer is already unreliable — maintaining it is dead weight and a correctness trap (a future delete path that forgets to decrement silently desyncs it). The `artwork.ref_count` column stays (no schema delta) but is UNUSED.

- `attachArtwork(contentHash:toTrack:)` — sets `tracks.artwork_key` and, when unset, the album cover: `UPDATE albums SET artwork_key=? WHERE id=? AND artwork_key IS NULL` (SQL guard, not read-then-write). No counter writes. Idempotent (re-attaching the same hash is a no-op UPDATE). Runs in the per-track txn (§6).
- `sweepOrphanArtwork() -> [(contentHash, cachePath)]` — authoritative by reachability: delete `artwork` rows `WHERE content_hash NOT IN (SELECT artwork_key FROM tracks WHERE artwork_key IS NOT NULL) AND content_hash NOT IN (SELECT artwork_key FROM albums WHERE artwork_key IS NOT NULL)` (the `IS NOT NULL` filters avoid the SQL `NOT IN (…,NULL)` never-true trap). Runs once at end-of-pass (non-cancelled only); returns swept `(hash, path)` so the caller does `cache.removeFiles(...)`. No `detachArtwork` needed — a re-link just overwrites `artwork_key` and the old hash falls out of reachability, swept on the next sweep.

## 8. VM seam + DAO additions

- New `Sources/AdaptiveSound/AudioViewModel+LibraryMetadata.swift` (mirrors the scan seam: `@MainActor` inheritance, progress hop via `Task { @MainActor in }`, only Sendable crosses). `runMetadataPass(_:generation:)` chained after `publishScanResult`; `@Published var metadataProgress: MetadataProgress?`; build the `ArtworkCache` in `makeLibraryStore` from `defaultArtworkCacheURL()`.
- DAO additions: `tracksNeedingMetadata(limit:)` (`+Reads.swift`), `markMetadataScanned` + `attachArtwork`/`detachArtwork`/`sweepOrphanArtwork` (`+Facets.swift`, beside `linkArtwork`), one-line `metadata_scanned = 0` reset in `upsertOne`'s modified branch (`+DAO.swift`).

## 9. Dependency-graph & build wiring

The extractor needs the FFmpeg C bridge (via `DeviceBridge.h`), which lives in `AudioDSP`. **Add `LibraryScan → AudioDSP`** in `Package.swift` (acyclic — `AudioDSP` depends on no Swift library target; VET-confirmed).

**Build-wiring (VET BLOCKER — required):** the `AudioDSP` dep supplies the C bridge but NOT the Swift-visible frameworks the extractor/cache `import`. `LibraryScan` currently links no frameworks, so it must gain its OWN `linkerSettings: [.linkedFramework("AVFoundation"), .linkedFramework("ImageIO"), .linkedFramework("CoreGraphics")]` (CryptoKit + Foundation autolink). This covers both the app link and the `VerifyLibraryStore` executable link (which gains them transitively). The alternative (extractor in the app target) is rejected: the app/executable target isn't `@testable`-importable, so the harness couldn't exercise it.

## 10. Test plan

**Vehicle: extend the `VerifyLibraryStore` executable harness** (currently 25/25). Rationale: all store+scanner behavioral tests already live there driving the REAL store on REAL temp trees; there is **no** LibraryStore/LibraryScan `.testTarget` (the two swift-testing targets are VM/DSP-only) so a new target = churn + fragmentation. Pure-unit helpers (`thumbnailPath`, sha256-hex) MAY go in swift-testing (now that `swift test` works, 71/71) if convenient; the **integration** cases stay in the harness.

**Fixtures — self-made, public-domain (NOT copyrighted):** generate a ~0.3 s self-authored sine tone, encode per format, write known tags + a self-generated 64×64 solid-color PNG cover (known sha256) via the `ffmpeg` CLI (dev tool). Check in tiny (<30 KB each) under `Tests/Fixtures/artwork-audio/`: `fixture.m4a` (AVFoundation path), `fixture.flac` (FFmpeg path), `no-tags.m4a` (stripped). Add a `make regenerate-metadata-fixtures` recipe recording the exact invocations + the cover's expected hash (auditable provenance). **The checked-in fixtures are AUTHORITATIVE — `make gate` NEVER runs `ffmpeg`** (a builder may lack it; encoder container bytes aren't byte-deterministic). M3's known-sha256 hashes the **authored cover PNG bytes**; the regen step verifies the extracted embedded bytes equal the input PNG.

**Cases** (`ChecksMetadata.swift` + `ChecksArtwork.swift` + `MetadataFixtureBuilder.swift`, registered in `allCheckCases()`):
- **M1/M2** extraction correctness — AVFoundation (`fixture.m4a`) and FFmpeg (`fixture.flac`) paths reach the store identically (title/track/disc/year, resolved artist+album, genre, duration/sr/channels).
- **M3** artwork dedup + ref_count — two tracks, same cover → ONE `artwork` row, both `artwork_key` equal, album art set, **original + `<hash>.thumb.jpg` exist**, thumb max edge ≤ 512.
- **M4** orphan cleanup — delete one track (row stays); delete the second → `sweepOrphanArtwork` removes the row AND both cache files.
- **M5** re-link — retag to a different cover (mtime bump → `metadata_scanned` reset) → old art decremented/swept, new art at the track, `artwork_key` updated.
- **M6** idempotency — second pass with no FS change: `tracksNeedingMetadata` empty, columns/rows/counts unchanged; a counting extractor is invoked 0×.
- **M7** no-tags anti-loop — `no-tags.m4a` marked scanned, columns stay NULL, **second pass still finds nothing** (the case the NULL-driven option fails).
- **M8** FS-tolerance — delete a file before the pass → skipped, marked, no crash, row survives, siblings extract.
- **M9** cancellation — cancel mid-batch (parked-rendezvous idiom from `checkReadsDuringScan`) → applied rows correct + marked, no torn artwork row, `sweepOrphanArtwork` NOT run, no crash.
- **M10** undecodable-art — garbage cover bytes → original cached, no thumb, size `.zero`, pass completes.
- **M11** bridge safety — run the FFmpeg-metadata path (M2's `fixture.flac`) under an **ASan/LSan** build of the harness to catch a leak/double-free in the new callee-owned-buffer C bridge (the C++ `make sanitize` gate doesn't reach it).

Teardown extends `cleanupScanFixtures()` to also drop the per-run artwork temp dir (keep-on-fail policy unchanged).

## 11. Architect vet — GO-WITH-CHANGES (resolved 2026-07-03)

Vetted (architect-reviewer): well-grounded, honors the single-writer + FS-divergence invariants, sets up S8.4/S9 cleanly, no corner-painting. One build BLOCKER (folded into §9) + refinements — all applied above. Resolutions:
- **(a) `LibraryScan → AudioDSP`** — acyclic, GO; but it does NOT supply the extractor's Swift frameworks → **§9 now adds explicit `linkedFramework`s to `LibraryScan`** (the BLOCKER). App-target alternative correctly rejected (not `@testable`-importable).
- **(b) marker = generation** (not bool) — confirmed. Reset lives in the gated `DO UPDATE SET` (fires only when a content field differs), NEVER in the unconditional `stampLastSeen` liveness bump — so a pure `last_seen_scan` refresh can't reset it (§5).
- **(c) ref_count** — **drop the incremental counter; sweep by pure reachability** (§7 rewritten). Keep the column vestigial (no schema delta).
- **(d) album art "first track wins"** — acceptable for S8.3; caveat: it's "first *applied*" (TaskGroup completion order → nondeterministic across runs), fine for a rebuildable cache; deterministic ordering deferred as gold-plating.
- **(e) FFmpeg C bridge** — sound, but a NEW callee-owned-buffer contract (NOT the opaque-handle idiom). Invariants (§3): both fns `noexcept`; interior storage C `malloc`/`av_malloc` only (never `new`/STL — would `terminate` under `-fno-exceptions`); `ffmpegMetadataFree` idempotent + safe on a zero-initialized struct; Swift zero-inits before the call, frees under `defer`. Covered by test M11 (ASan/LSan).
- **(f) concurrency** — sound under Swift 6 + the single-writer invariant; apply+link+attach+mark folded into ONE per-track txn (§6) so cancellation can't leave a written-but-unmarked row; concurrency capped `min(activeProcessorCount, 6)`.

VERDICT: GO-WITH-CHANGES → all changes applied; design is implementation-ready.

## 12. Verification (definition of done)
`swift build` clean · `swift test` green · `make gate` (VerifyLibraryStore now with M1–M10 + VerifyAUGraph + C++ null **119/0**, golden master `0xE7267654BA01D315` unchanged — no DSP change here) · `make sanitize` · `make tsan` · swiftlint --strict. Commit per the per-chunk pace.
