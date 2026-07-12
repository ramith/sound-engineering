# S8.4 — Live-Watch + Move-Matching + Facet-Orphan Sweep (Design)

**Document ID:** S8.4-DESIGN-001
**Status:** DESIGN — synthesized from a tech/ux/qa lens strategy; **pending founder manual review + architect-reviewer vet**. Founder process for this chunk: doc/requirement review → tech/ux/qa design → review → architect review → **manual review** → implementation plan → **manual gate** → implement → test → **manual test** → commit.
**Chunk of:** S8 (library spine). Builds on shipped S8.1 (store), S8.2 (folder scan + move-signature *population*), S8.3 (metadata + art). See [s8-2-folder-scan-design.md](s8-2-folder-scan-design.md).
**Authored by:** team — swift-expert (tech), qa-expert (verification), ux-researcher (UX), synthesized by the orchestrator. Working lens artifacts in the session scratchpad (`S8.4-lens-{tech,qa,ux}.md`).

## What S8.4 does

Three deliverables, one theme: **make the persistent store track the filesystem live, without ever losing durable track identity.**

1. **Live-watch (FSEvents).** Recursively watch registered scan roots *while the app is open* and reconcile changes into `LibraryStore` in the background. Today only the on-demand full re-scan writes the store; the existing monitor ([AudioViewModel+FolderMonitor.swift](../../Sources/AdaptiveSound/AudioViewModel+FolderMonitor.swift)) is non-recursive and only refreshes the *in-memory* playlist.
2. **Move-matching.** Consume the `(dev,inode,size,mtime)` signature S8.2 already populates so a moved/renamed file reconciles via the id-preserving `moveTrack` — **not** delete+insert (which mints a new id and would silently drop the track from future playlists/counts). This is the explicit hard gate **SEQ-1 / Gate-2** ([known-issues.md](../product/known-issues.md)).
3. **SF-2 `sweepOrphanFacets()`.** Reap zero-track `albums`/`artists`/`genres` left by move/retag/delete churn (preserving the `artists(id=0)` sentinel), mirroring the shipped `sweepOrphanArtwork`, so S9 browse shows no phantom empties.

Plus one cross-cutting **correctness guard** all three lenses independently flagged as the top risk: an **unmounted external/network volume** must never be read as a mass user-deletion.

### Non-goals (scope boundaries — enforced)
- S9 browse UI. S8.4's reconcile is **background/headless**, additive; the visible list stays the in-memory `playlist` until S9 swaps to store-reads.
- S10 playlists/queue; online metadata enrichment; the SF-4 dedicated read-pool; any DSP/audio change.

---

## 1. FSEvents live-watch

### 1.1 Where it lives + the LOGIC/PLUMBING split (the load-bearing testability decision)

The single most important structural decision (QA + tech agree): **separate the reconcile LOGIC from the FSEvents PLUMBING.**

- **PLUMBING** — a new `Sources/LibraryScan/LibraryWatcher.swift` (headless target, no AppKit): FSEvents → debounce/coalesce → emit a `Sendable` path/flag batch to a sink. Contains **no** store/reconcile logic.
- **LOGIC** — the reconcile is the *already-shipped, already-tested* `LibraryScanner.scan(...)` path (§2). It contains **no** FSEvents. Every move/delete/facet case is verified by mutating a real temp tree then calling `scan` directly, exactly as today's `reconcileDelete`/`reconcileRename` checks do.

Result: ~90% of S8.4 stays as deterministic as today's 36 checks; FSEvents (the only non-deterministic part) gets a single, injectable-seam test (§5).

### 1.2 API + flags

Apple-native `FSEvents` (founder "right-tool" principle — no third-party watcher):
`FSEventStreamCreate` + `FSEventStreamSetDispatchQueue(stream, watcherQueue)`; flags **`FileEvents | NoDefer | WatchRoot | IgnoreSelf`**; latency **1.0 s** (OS coalesces the raw storm before it even wakes us).

- **`FileEvents`** — per-*file* paths; also gives paired `ItemRenamed` legs (old+new) useful for moves.
- **`NoDefer`** — first event of a burst delivered promptly, rest coalesced over `latency`.
- **`WatchRoot`** — fires `RootChanged` if a watched root is renamed/deleted/unmounted → our primary unmount/root-gone signal (§4).
- **`IgnoreSelf`** — belt-and-braces; the store + artwork cache live under App Support, not under a watched root, so no feedback loop.

**One multi-path stream for all roots** (roots are disjoint — nested/overlapping rejected at registration): one callback, one queue, one teardown. Add/remove a root = stop→invalidate→release→recreate with the new path list (infrequent; on Choose-Folder / remove-folder only).

### 1.3 `sinceWhen` — `kFSEventStreamEventIdSinceNow` (not persisted replay)

Only watch *future* events; rely on the existing full re-scan (at addRoot / next launch) to catch up anything changed while closed. Persisting + replaying an event-id stream would be a second, redundant reconciliation path — and it is unreliable exactly when it matters (volume eject invalidates the event-id space). Deferred as a *measured* optimization (device-UUID-validated replay) if huge-library launch time ever becomes a real complaint.

### 1.4 Swift-6 isolation + clean teardown (the SIGTRAP lesson, applied)

The current monitor documents a hard runtime crash: a background-queue handler touching `@MainActor` state traps at quit (EXC_BREAKPOINT), invisible to build+lint ([AudioViewModel+FolderMonitor.swift:22-38](../../Sources/AdaptiveSound/AudioViewModel+FolderMonitor.swift)). Applied here:

- The FSEvents C callback is a top-level `@convention(c)` function; it copies the C `char**`/flags into a `Sendable [WatcherEvent]` synchronously on the watcher's **serial** queue and hands it to a stored `@Sendable (WatcherEventBatch) -> Void` sink. **No `@MainActor` state is touched on the background queue.**
- The VM's sink does `Task { @MainActor [weak self] in … }` *first*, then debounces — exactly `scheduleFolderReload`'s pattern.
- `LibraryWatcher` is `@unchecked Sendable` (all mutable state confined to its serial queue — the same justification as `DispatchSource` usage / `OneShotLatch`). `info` pointer is `passUnretained`; ordered teardown guarantees the stream is stopped before deinit.
- **Teardown ordering (mandatory):** on `stop()`, synchronously on the watcher queue: set `torn=true` → `FSEventStreamStop` → `FSEventStreamInvalidate` → `FSEventStreamRelease` → nil. Slotted into `shutdown()` next to `stopFolderMonitoring()`, before `performStop()`/`engine.shutdown()`:

```
stopSpectrumTimer(); stopFolderMonitoring()
libraryWatcher?.stop()      // NEW — ordered FSEvents teardown
reconcileTask?.cancel()     // NEW — mirrors scanTask cancel
scanTask?.cancel(); await performStop(); try await engine.shutdown()
```

### 1.5 Coexist with the current DispatchSource monitor (R1)

The old monitor drives the *visible* in-memory playlist (`loadMusicFolder`) — an S9-owned concern S8.4 must not change. The FSEvents watcher drives a *different* sink (store reconcile only). **Keep both, independent, additive** (as S8.2b already established). They do disjoint work, each debounces independently, the store reconcile is idempotent. Merging them onto one stream is an explicit **S9 cleanup** (when the visible list becomes a store-read).

### 1.6 Limitation: FSEvents is a LOCAL-volume facility (red-team F2)

FSEvents does **not** reliably deliver events for **network volumes (SMB/AFP/NFS)** — and audiophile libraries are frequently on a NAS. Consequences, stated so no one assumes live-watch is universal:
- For a **network root**, live-watch will simply not fire; that root reconciles only **on demand** (user re-picks the folder) and **at launch/next explicit scan**. This is a *feature gap*, not data loss.
- FSEvents also won't deliver `RootChanged` for a NAS going offline — so the §4 unmount guard's **volume-mounted + path-resolves precheck (not FSEvents)** is the real protection for network roots.
- **R1 scope:** wire live-watch for local volumes; detect a network root (`URLResourceValues.volumeIsLocalKey`) and skip starting a stream for it (log that it's on-demand-only). A periodic-poll fallback for network roots is a deferred enhancement, not R1.

---

## 2. On-event reconcile strategy

### 2.1 Decision: debounced FULL re-scan of the affected root (R1)

On a debounced FS change for a root, run the existing `LibraryScanner.scan(root:folderID:into:progress:)` for that root (the move-matcher, §3, lives inside its upsert path, so it fires for both on-demand and live reconciles). Rejected for R1: targeted incremental subtree reconcile — it needs a new subtree-scoped sweep predicate (`WHERE url LIKE '<subtree>/%'`), new correctness surface (LIKE-escaping, cross-subtree moves straddling two sweeps) — the exact "artifact-prone complexity" the founder's principle says defer until *measured* need.

Rationale: reuses every FS-divergence invariant the S8.2b harness already proves; the matcher lands in one place; library scale (thousands of files, Apple-Silicon SSD, lazy 256-batch walk with short actor hops) makes a coalesced full re-walk sub-second-to-low-seconds and invisible at `.utility` QoS. **UX tension noted:** the UX lens prefers scoped reconcile as the biggest energy lever; the counter is that it's headless/background/debounced, so the energy delta is muted and not worth the complexity at R1. → **Open Decision D3** (recommend full re-scan; migrate to scoped only on a measured trigger, mirroring the SF-4 escape-hatch posture).

### 2.2 Coalescing / debounce

Two-stage: FSEvents `latency = 1.0 s` (OS-side) + a VM-side **per-root ~1.0 s debounce** after the last callback, with a **~5 s max-latency cap** so a *continuous* import still commits periodically instead of starving. Net worst-case staleness ≈ ~2 s — invisible for a background reconcile. Per-root, so a change in root A never delays root B. (Distinct from the visible monitor's 100 ms; the store reconcile is heavier and invisible, so it coalesces harder.)

### 2.3 New VM seam + serialization

- New `reconcileRoot(folderID:root:)` / `performReconcile(folderID:root:store:)` (a sibling of `scanFolderIntoLibrary`/`performScan`, minus the validate/`addRoot` preamble, plus the §4 reachability guard). Reuses `LibraryScanner.scan` + `runMetadataPass` + `sweepOrphanFacets` (§3.4). Publishes results like `publishScanResult` so S9 wiring is uniform.
- New `reconcileTask` (mirrors `scanTask`); a re-trigger cancels the prior reconcile.
- **Per-root serialization gate** `reconcilingRoots: Set<Int64>` so at most one structural pass (scan OR reconcile) runs per root at a time. **Note (architect SF-b):** generations are NOT per-root — `beginScanGeneration` allocates a single **global** `max(last_seen_scan)+1` (`LibraryStore+DAO.swift:117`); the isolation that lets root A reconcile while root B scans comes from the sweep being **folder-scoped** (`sweepOrphans(inFolders:[folderID]…)`), not from generation isolation. → **Open Decision D4** (recommend per-root Set over a global lock).

---

## 3. Move-matching (id preservation — the Gate-2 blocker)

### 3.1 The bug, precisely

During a walk the moved file is seen at its NEW path; `upsert` keys on `url`, finds nothing, INSERTs a new row (new id); the OLD row (old url, `last_seen_scan < gen`) is then deleted by the end-of-walk sweep. Net: the durable id changes → future playlist/count references orphaned. `checkCrossDirMove` currently asserts this *wrong* delete+add outcome as a placeholder.

### 3.2 Placement: in the per-file upsert path (new `upsertReconciling`)

When a file classifies `.new`, probe `idx_tracks_dev_inode` for exactly one *unswept* row with the same signature; if found, `moveMatched` (id-preserving) instead of insert. Chosen over a post-walk pairing pass because: the sweep is end-of-walk and the matched row is *stamped current* so the sweep simply never sees it (no sweep special-casing); it folds into the existing one-transaction-per-256-batch shape; and it composes with the full-re-scan strategy (§2.1) for free.

`LibraryScanner.walk` swaps `store.upsert(…)` → `store.upsertReconciling(…)`. Per file, inside the batch transaction:
1. Row already at this url (`.unchanged`/`.modified`) → normal `upsertOne` (**no** move probe — a file at its known url is not a move).
2. `.new` + `inode`/`dev` present → `moveCandidate(for:generation:)`:
   - exactly one → `moveMatched(...)`; on `URLConflict` → fall back to `upsertOne` (safe: treat as new).
   - zero / ambiguous / nil signature → `upsertOne` (insert new).

### 3.3 CRITICAL: the moved row must be stamped `last_seen_scan = gen`

`moveTrack` updates **only** url/folder/relative_path — it does **not** stamp `last_seen_scan`, so a move-matched row would still be `< gen` and the end-of-walk sweep would **delete it** (the bug in subtler form). Fix: a **new** DAO op `moveMatched(id:to:newFolderID:generation:)` that does the id-preserving move **AND** stamps `last_seen_scan = gen` **AND** refreshes the signature, in **one transaction**. It reuses `moveTrack`'s `URLConflict` pre-flight. It does **not** reset `metadata_scanned` (a pure move doesn't change content → tags stay valid, no needless re-extraction). `moveTrack` stays pure (user/explicit primitive); `moveMatched` is the scan-owned variant.

### 3.4 New DAO ops (architect MF-1, MF-2 applied)

- `moveCandidate(for file: ScannedFile, generation: Int64) throws -> Int64?` — prepared `SELECT id FROM tracks WHERE dev=? AND inode=? AND file_size=? AND mtime=? AND format=? AND last_seen_scan<? AND url<>? LIMIT 2`. Exactly one → that id; zero/two → nil (LIMIT 2 = cheap "unique?" test). **`format` is safe corroboration (MF-1):** a legitimate audio→audio rename/move keeps its extension, so `format` never breaks a real match, yet it blocks an inode reused by a *different-format* file. **`name` is deliberately NOT in the predicate:** a same-dir rename *changes* the basename (the M1 headline case), so requiring `name` equality (the architect's first suggestion) would break rename detection — rejected. The residual inode-reuse false-match (a *different* file coincidentally sharing dev+inode+size+whole-second-mtime+format) is the documented F4 near-impossibility; `content_hash` (`Schema.swift:113`) is the principled future fix. Expose the pure candidate-selection as a unit-callable seam so cross-volume / ambiguity cases are testable without staging two volumes (QA QD-2).
- `moveMatched(id: Int64, to file: ScannedFile, newFolderID: Int64?, generation: Int64) throws` (**MF-2**) — takes the FULL `ScannedFile` and, in ONE transaction: UNIQUE(url) pre-flight (typed `URLConflict`, reusing `moveTrack`'s belt-and-braces) → UPDATE **url, folder_id, relative_path, name, format, file_size, mtime, inode, dev** → stamp **`last_seen_scan = gen`**. `relative_path`/`name` MUST refresh from the `ScannedFile` (a rename changes `name`; a cross-dir move changes `relative_path`, computed by `RelativePathResolver` against the current root — `LibraryScanner.swift:174`); leaving them stale reintroduces the exact bug `moveTrack`'s comment warns of (`LibraryStore+DAO.swift:190-193`). Does NOT touch `metadata_scanned` (pure move → tags stay valid).
- `upsertReconciling(_:folderID:generation:) throws -> [Int64]` — batch write, probe-or-upsert per element, one txn (§3.2). Used by `walk` unconditionally, so **both** on-demand and live reconciles get id-preserving moves.

### 3.5 Safety policy (every ambiguity resolves to the safe side)

A wrong id is *silent corruption* (a playlist entry points at the wrong song); a new id is *recoverable* (the track reappears, just detached). So:
- Primary key `(dev,inode)` (volume-scoped); size+mtime corroborate.
- `> 1` candidate → **no match, treat as new**. Nil inode/dev → **no match**. `URLConflict` → fall back to upsert.
- Move **that also edited content** (size/mtime differ) → not signature-identical → treated as new+sweep. Correct default; → **Open Decision D5** (recommend full-signature equality for R1; defer inode-only matching).
- **Move-matching only survives inode-PRESERVING moves (red-team F3).** A same-volume Finder rename/drag preserves the inode (matched ✓). But a *copy-then-delete* move — cross-volume drag, `rsync --remove-source-files`, some sync tools — gives the destination a **new** inode → not matched → id + user-state lost. The unused `content_hash` column (`Schema.swift:113`) is the deferred escape hatch for content-based matching; out of scope for R1. State the gap; don't pretend all "moves" are covered.
- **An unmatched/ambiguous move still sweeps the OLD row's user-state (red-team F4).** "New id is recoverable" is only half true: the old row's `play_count`/`loved`/`rating` are deleted by the end-of-walk sweep along with its id. Treat-as-new is the safer of two bad options (guessing risks assigning state to the WRONG track), but it is **not lossless** — say so. Note the reasoning "distinct files have distinct inodes" holds only for *coexisting* files; inode reuse across a delete+recreate with matching size + whole-second mtime could, in theory, mis-assign an old row's state — vanishingly rare, but a *known limitation*, not an absolute guarantee.
- Whole-second mtime collisions can't cause a *false* match between coexisting files (distinct inodes); they can only fail to disambiguate → LIMIT-2 guard → treat as new. Safe.

### 3.6 SF-2 `sweepOrphanFacets()`

Reachability sweep mirroring `sweepOrphanArtwork` (not a ref-counter — counters desync, the shipped design's lesson). One transaction, ordered **albums → artists → genres**:
1. `DELETE FROM albums WHERE id NOT IN (SELECT album_id FROM tracks WHERE album_id IS NOT NULL);`
2. `DELETE FROM artists WHERE id <> 0 AND id NOT IN (SELECT artist_id FROM tracks WHERE artist_id IS NOT NULL) AND id NOT IN (SELECT album_artist_id FROM albums WHERE album_artist_id IS NOT NULL);` — the `id <> unknownArtistID` clause is **mandatory** (the sentinel backs the M1 album key); the two-arm reachability KEEPS an artist referenced only as an album_artist (else `ON DELETE SET DEFAULT` would silently rewrite that album's artist to the sentinel).
3. `DELETE FROM genres WHERE id NOT IN (SELECT genre_id FROM track_genres);`

Albums-before-artists so a dead album's references are gone before the artist reachability check. Returns `(albums:Int, artists:Int, genres:Int)` for logging/verification. **Run it BEFORE `sweepOrphanArtwork`** (deleting an album nulls its `artwork_key`, orphaning art the artwork sweep then reclaims). It is **library-wide reachability** (NOT folder-scoped — a facet used by a track in another folder is kept). Gate it on churn (`orphansSwept>0 || metadataApplied>0`) to avoid three anti-joins on every steady-state pass → **Open Decision D6** (recommend gated). GRDB's single writer serializes it against the metadata resolvers; cross-instance it's write-locked by `BEGIN IMMEDIATE` and idempotently recoverable — same posture as the artwork sweep.

**Also call it from `removeRoot` (red-team F5 + architect SF-c).** `removeRoot` deletes a folder's tracks *outside* the scan/reconcile path (`LibraryStore+DAO.swift:101`), so it can leave orphan facets no later reconcile is guaranteed to clean. It should sweep facets+artwork after its delete — **but** `removeRoot` already wraps its work in one `connection.transaction {}`, and `sweepOrphanFacets()` opens its own `BEGIN IMMEDIATE`; SQLite can't nest transactions. So provide a no-txn **`sweepOrphanFacetsLocked()`** (mirroring `applyMetadataLocked`/`attachArtworkLocked`) and call the *locked* form inside `removeRoot`'s existing transaction.

---

## 4. Volume-unmount guard (highest-stakes correctness call)

**Invariant: absence of a volume must NEVER read as user-deletion.** A reconcile of a root on an unmounted external/NAS volume enumerates zero files → the sweep deletes **every** row and their user-authored state (play-counts/ratings/loved/future playlists), with no undo. External/NAS libraries + eject/undock/sleep are the audiophile *norm*, so assume this happens constantly.

**Reachability is decided by the volume + path, NOT by `st_dev` equality** (see red-team **F1**, §9). `LibraryScanner.isRootReachable(_:) -> RootReachability`:
- **`reachable`** — the root's volume is present in `FileManager.mountedVolumeURLs` AND the root path resolves to a readable directory → proceed (scan+sweep+facet sweep). A legitimately *empty* reachable root still sweeps (a genuine "deleted every song" case).
- **`rootMissingVolumeMounted`** — volume mounted but the root path is gone → genuinely **deleted** root → sweep is correct (preserves the existing `vanishedRootFullSweep` test).
- **`volumeUnreachable`** — the root's volume is NOT mounted → **skip: no walk, no sweep, no facet sweep**; log; leave the watcher registered.

**Why not `(dev,inode)` as the gate (red-team F1):** `st_dev` is assigned at mount time and **changes across an eject+remount**, so a `(dev,inode)`-equality gate would read a normally-remounted drive as permanently "unreachable" → the library silently stops reconciling after the first reconnect. So `(dev,inode)` is used only as a *soft identity hint* to catch the exotic "a different volume mounted at the same path," and on a confirmed remount we **re-stamp `folders.dev/inode`** from the live values (trusting the path once the volume is back). The mass-sweep protection rides on volume-mounted + path-resolves, which are remount-stable.

Enforced **twice**: a VM precheck in `performReconcile`/`performScan`, AND a scanner backstop. **The backstop is a MAGNITUDE gate, not a stat-based binary (architect MF-4):** `isRootReachable` proves the root dir is *stat-able*, not that its contents are *enumerable* — a half-dead SMB/autofs mount can `stat` the root while `enumerator` yields zero. So the rule is: **if the walk saw `filesSeen == 0` but the store already held N>0 rows for this root, SKIP the sweep regardless of reachability** (log "enumerated empty but store had N rows — refusing destructive sweep, will retry next reconcile"). The only thing this blocks is a genuinely-emptied *reachable* root (rare; self-heals next reconcile) — vastly cheaper than deleting N rows + user-state on a zombie mount. Deletion is thus positively evidenced by a successful non-empty walk, never inferred from an empty one. Surfaced as a typed `RootUnreachableError` the VM catches silently like `CancellationError` (no `ScanResult` churn) → **Open Decision D7** (recommend typed throw). `NSWorkspace` mount/unmount notifications are an optional *responsiveness* trigger (defer for R1).

---

## 5. Test plan (headless `VerifyLibraryStore`; ~36 → ~44 checks)

Real temp trees under `test-data/` (never /tmp), UUID-unique, cleaned on success / kept on failure, VerifyAUGraph idiom. New files: `ChecksMoveMatch.swift`, `ChecksFacetSweep.swift`, `ChecksFolderWatch.swift`. Master matrix (folded into ~8 numbered `CheckCase`s):

| # | Area | Assertion |
|---|------|-----------|
| M1 | rename (same dir) | id PRESERVED, `orphansSwept==0`, one row at new path, `relative_path` updated — **upgrades `reconcileRename`** |
| M2 | cross-dir move | id preserved, `relative_path`/`folder_id` correct, `orphansSwept==0` — **upgrades `checkCrossDirMove`** |
| M3 | **reference-survives-move** | `play_count`/`loved`/`rating` set pre-move survive on the SAME id — **Gate-2 proof; hard-fail if reset** |
| M4 | cross-volume same-inode | differing `dev` ⇒ no match ⇒ delete+add (synthetic rows via the pure candidate fn) |
| M5/M6 | ambiguous ≥2 (both directions) | no move, no mis-pair (uniqueness required both sides) |
| M7 | target-url collision | typed `URLConflict`, no silent merge, both ids survive |
| M8/M9 | genuine delete / genuine new | no candidate ⇒ swept (id gone) / new id, `orphansSwept` correct |
| M10/M11 | modify-in-place / copy | same-url `.modified` (not a move) / different-inode copy (not a move) |
| M12 | whole-second mtime collision | inode disambiguates ⇒ correct row moved, sibling untouched |
| F1–F3 | facet zero-track album / referenced album / album-artist-only artist | swept / kept / **kept** (two-arm reachability) |
| F2 | **id-0 sentinel** | **NEVER swept** (all-untagged lib) — hard-fail if gone |
| F5–F7 | genre orphan / idempotent / cross-folder reference | swept / 2nd call returns 0 / kept (library-wide reachability) |
| V1 | volume-unmount / missing root | zero-enumeration ⇒ ALL rows survive, `orphansSwept==0`, facet-sweep skipped — **hard-fail if swept** |
| V2 | volume-unmount / identity mismatch | re-created-different root ⇒ refuses destructive sweep |
| W1–W3 | FSEvents plumbing (synthetic `ingest`) | debounce coalesces N events → expected dirty set; `RootChanged`/`MustScanSubDirs` route to guard/full-rescan; TSan-clean |
| W4 | FSEvents real-stream smoke | **manual subcommand only** (`--fsevents-smoke`), `withDeadline(10s)` poll — never in `make gate` |
| R1 | regression | all existing checks green; only `reconcileRename` + `checkCrossDirMove` change semantics |

**Architect-added cases (must-fix verification):** **M13** swap/rotation — A↔B (distinct inodes) each lands on its OWN correct file (MF-1); **M14** cross-root move — a file dragged A→B, re-scan only B → id preserved, `folder_id==B`, no dup in A (works because `beginScanGeneration` is global-monotonic — SF-a); **F-attribution** — after a facet sweep, a surviving album's `album_artist_id` is NOT rewritten to the id-0 sentinel (MF-3); **V3** zombie-mount — a *reachable* root whose walk returns 0 files while the store holds N>0 → sweep REFUSED (MF-4).

**FSEvents determinism** is solved by the §1.1 split: logic tested by direct `scan` calls; plumbing tested by an injectable `ingest(rawEvents:)` seam (deterministic, no `sleep`, no OS scheduler); the real stream is a manual smoke. TSan (`make tsan` / `sanitize-library-store`) covers the synthetic-ingest path so the Swift-6 background-isolation trap surfaces as a race, not a probabilistic quit crash. `make gate` picks up the new checks with **zero Makefile change**.

**Needs a harness hook (QA QD-1):** no write op exists for `play_count`/`loved`/`rating`. Add a labeled `setUserState(trackID:…)` in `LibraryStore`'s "Verification hooks (NOT the DAO)" section (real play-count writes are S10) — required to prove M3.

---

## 6. Decisions for founder / architect (each with a recommendation)

| # | Question | Recommendation |
|---|----------|----------------|
| **D1** | Catch up changes made while the app was closed via saved-event replay, or a full re-scan? | **Full re-scan** (simpler, reliable). Defer replay unless launch time becomes a real complaint. |
| **D2** | Auto re-scan saved roots at app launch? | **Split (architect):** defer auto-rescan for LOCAL roots (FSEvents catches them live once open), but **auto-rescan NETWORK roots at launch** — they have no live-watch (F2), so launch is their only automatic catch-up. Cheap (the reconcile path already exists). (Founder call.) |
| **D3** | On a live change, full re-scan the root, or reconcile just the changed files? | **Full re-scan** for R1 (reuses proven path, matcher in one place). Go scoped only if a big library measurably drags. |
| **D4** | One reconcile at a time globally, or per-root? | **Per-root** (root A reconciles while you scan root B). |
| **D5** | A file that was moved *and* edited — keep its identity? | **Treat as new** for R1 (safe). Preserving id across move+edit is riskier; defer. |
| **D6** | Run the facet cleanup every pass, or only after churn? | **Only after churn** (a pass that swept/moved/retagged) — avoids wasted work. |
| **D7** | Signal "root unreachable" as a thrown error or a result flag? | **Thrown error** caught silently (smaller blast radius, matches existing idiom). |

---

## 7. Implementation slices (store/scanner first — each headless-verifiable before any FSEvents risk)

1. **Move-matching** (the Gate-2 blocker): `moveCandidate` + `moveMatched` + `upsertReconciling`; `walk` uses `upsertReconciling`; `setUserState` hook; upgrade `reconcileRename` + `checkCrossDirMove`; add M3–M12. **No FSEvents, no VM change** — unblocks SEQ-1/Gate-2 on its own.
2. **SF-2 facet sweep**: `sweepOrphanFacets()` + F1–F7 + the artwork-interaction assertion. Store-only.
3. **Unmount guard**: `isRootReachable` + `RootUnreachableError` + scanner backstop + injectable probe; V1/V2; keep `vanishedRootFullSweep`. Store/scan level — the guard exists the moment reconcile does.
4. **FSEvents watcher (mechanism)**: `LibraryWatcher` + `WatcherEvent(Batch)` + `ingest` seam + W1–W3. Headless, no VM.
5. **VM wiring (policy)**: `libraryWatcher`/`reconcileTask`/`reconcilingRoots`; `reconcileRoot`/`performReconcile`; sink→debounce→reconcile; `shutdown()` teardown; call `sweepOrphanFacets` post-metadata; observable state (`isReconciling`/`lastReconciledAt`/`lastReconcileError`/per-root `reconcileState`) for S9. Coexists with the DispatchSource monitor. Founder does the by-ear/by-eye live check here.

Ordering rationale: slices 1–3 are store/scanner-only, fully headless-verifiable, and each closes a distinct gate (move-id, facet phantoms, unmount-safety) with zero FSEvents risk. Live-watch lands last, on a proven foundation — matching "correctness over demoability."

---

## 8. Definition of Done

- `swift run VerifyLibraryStore` exits 0 — existing checks green (only `reconcileRename`/`checkCrossDirMove` semantics change) + all S8.4 cases (§5) incl. the Gate-2 reference-survives-move proof, id-0 sentinel preservation, and V1/V2 unmount safety.
- `make gate` + `make sanitize` + `make tsan` + `sanitize-library-store` green (TSan covers the synthetic-ingest watcher path). Null-test golden master untouched (S8.4 touches no DSP).
- swiftlint `--strict` clean; no force-unwraps; Swift-6 language mode (data-race free).
- **SEQ-1 / Gate-2 closed**: a moved track keeps its id and user-state. Update `known-issues.md` (SEQ-1 Gate-2) accordingly.
- Architect-reviewer GO; founder manual review + manual test (live copy/move/delete reconciles the store without disturbing the visible playlist; eject/reconnect a drive leaves rows intact).

---

---

## 9. Red-team review — findings folded in

A pre-mortem/red-team pass (the-fool) stress-tested the design for silent data loss of durable identity / user state. Five findings, all now folded into the sections above:

| # | Severity | Hole | Where fixed |
|---|----------|------|-------------|
| **F1** | HIGH | `(dev,inode)`-equality reachability gate breaks on eject+remount (`st_dev` is reassigned) → library silently stops reconciling after a reconnect | §4 — gate on **volume-mounted + path-resolves**; `(dev,inode)` demoted to a soft hint, re-stamped on remount |
| **F2** | HIGH | FSEvents doesn't fire on **network volumes** — but NAS libraries are common → live-watch silently dead for them | §1.6 — detect network roots, skip the stream, reconcile on-demand/launch; volume-check (not FSEvents) guards them |
| **F3** | MED | Move-matching only survives **inode-preserving** moves; copy-delete moves (cross-vol, rsync) lose id | §3.5 — stated as a known gap; `content_hash` is the deferred escape hatch |
| **F4** | MED | Unmatched/ambiguous move **still sweeps the old row's user-state** — "recoverable" oversold; inode-reuse caveat | §3.5 — honest framing as a known limitation |
| **F5** | LOW | `removeRoot` deletes tracks outside the reconcile path → orphan facets | §3.6 — call `sweepOrphanFacets`/`sweepOrphanArtwork` from `removeRoot` |

F1 and F2 materially changed the design (the reachability gate and the network-volume scope); F3/F4 are honesty/limitation statements that prevent a false sense of coverage; F5 is a small additive fix. New harness cases should cover the F1 remount path (re-stamp, resume) and the F2 network-root skip where feasible.

---

## 10. Architect review — verdict + resolutions

**Verdict: GO-WITH-CHANGES** (architect-reviewer, verified against the cited code). Core scheme fundamentally sound: `moveMatched` stamping `last_seen_scan = gen` in one txn genuinely closes the Gate-2 "sweep deletes the move" hole; the F1 unmount-gate pivot is correct and preserves `vanishedRootFullSweep`; the facet SQL (id-0 exclusion + two-arm reachability) is correct; the FSEvents isolation faithfully applies the SIGTRAP lesson. Four local must-fixes, all folded in:

| # | Must-fix | Resolution |
|---|----------|------------|
| **MF-1** | inode-reuse could silently assign a moved id to the WRONG file | Added `format` corroboration to `moveCandidate` + swap/rotation test (M13). **Rejected** the architect's `name`-corroboration — a rename changes the basename, so it would break the M1 rename case. Residual is the documented F4 near-impossibility; `content_hash` is the future fix (§3.4). |
| **MF-2** | `moveMatched` param list couldn't refresh `relative_path`/`name`/signature | `moveMatched` now takes the full `ScannedFile`, writes url/folder/relative_path/name/format/signature + stamp, one txn (§3.4). |
| **MF-3** | no test pinned "surviving album's `album_artist_id` not rewritten to sentinel" | Added the assertion (§5, F-attribution). |
| **MF-4** | unmount backstop was stat-based → a zombie SMB mount (stat-able, 0 files) still mass-sweeps | Backstop is now a **magnitude gate**: 0 files walked + N>0 rows stored → refuse sweep, regardless of reachability (§4). Test V3. |

Should-fixes folded: **SF-a** cross-root moves work via global-monotonic `beginScanGeneration` (documented + M14); **SF-b** corrected the "one generation per root" wording — isolation is folder-scoped-sweep, not generations (§2.3); **SF-c** `removeRoot` calls a no-txn `sweepOrphanFacetsLocked()` inside its own transaction (§3.6); **SF-e** `sweepOrphanFacets` guarded on `!Task.isCancelled` in the VM seam (skip on a cancelled reconcile, matching the artwork-sweep posture); **SF-d** two watchers on one dir is the intended R1 steady state (noted). Architect concurred with D1/D3/D4/D5/D6/D7; refined **D2** (auto-rescan network roots at launch — now in §6). Open risks accepted + tracked: F3/F4 copy-delete-move id loss (keep loud in known-issues); F2+D2 compounding for network roots (mitigated by the D2 split); `.reachable` stays stat-based (the MF-4 magnitude gate is the backstop).

---

**Next:** founder **manual review** of this design → implementation plan → **manual gate** → implement slices 1–5.
