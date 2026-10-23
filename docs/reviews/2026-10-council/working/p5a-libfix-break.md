# P5a break-it: the R1 library-sweep fix (`fix/library-sweep-evidence` @ 46c1276)

Commits under test: 763cb1b ("a sweep needs positive evidence"), 46c1276 ("a folder on the startup disk stays unbound").
I ran everything in my own worktree `.claude/worktrees/panel-p5a`, detached at 46c1276, against the real `LibraryScanner` /
`LibraryStore`, on temp dirs and real disk images (APFS, MS-DOS FAT32, ExFAT, via `hdiutil`). Every image attached was
force-detached; `mount | grep p5a-` = 0 after each run. Never the founder's library, never the app.
Tests (uncommitted): `Tests/LibraryBrowseKitTests/P5aFixBreakTests.swift`. Run: `swift test --filter P5aFixBreakTests`.
Log: `exp-p5a/fix-run1.log`. The fix's own suites (SweepEvidence, FolderWalkSchedule, G-LIB break-its: 22 tests) pass, and
VerifyLibraryStore passes 160/160 (exit 0, `exp-p5a/vls-fix.log`).

## Verdict: FIX-FIRST (one small change), then SHIP

The fix closes every case I originally reported (LIB-02a/b/d), and the new attacks on bound roots all hold. One
deterministic data-loss path is still open: **an UNBOUND root**. Every existing root migrates to v8 unbound
(`volume_uuid NULL`) and stays unbound until a walk finds it on a drive that has a UUID. While unbound, the root has
exactly the pre-fix P5A-02 behaviour (repro below: 37–30 of 40/30 songs swept, playlist entries and plays deleted). The
two-same-named-drives users the fix targets are the ones exposed in the window after the upgrade. The fix is small (S).

## 1. The original cases (all PASS now)

| Case | Before the fix (7d7c2cd) | At 46c1276 |
|---|---|---|
| LIB-02a `chmod 000` subfolder | swept 5; entry and plays gone | `refused(incompleteWalk)`, 10/10 rows, entries, plays; after restoring perms + 1 genuine delete: `ok(swept=1)` |
| LIB-02a `chmod 444` (r, no x) | swept 5 | the same as 000: refused, all kept; then swept exactly 1 |
| LIB-02b 800 songs, volume detached after batch 1 | swept 544, playlist 800 → 256, 24 re-keyed rows | `refused(rootVanished)`, 800/800/800, **no extra rows** (the `lstat` proof stops the re-keying); remount → `ok(seen=800 swept=0)` |
| LIB-02d same-named other drive at the path | swept 58–60, plus 2 false move-matches | `refused(differentVolume)`, 60/60/60, no foreign rows; original drive back + 1 delete → `ok(swept=1)` |
| Control: genuine delete, complete walk | swept 1 | swept 1 (in every case above) |

## 2. New attacks

| # | Attack | Result | Verdict |
|---|---|---|---|
| ATK-1 | Error at the root itself (`chmod 000` root) vs 5 levels deep | both `refused(incompleteWalk)`, 6/6 kept | PASS |
| ATK-2 | Symlink loops (`A/up → ..`, `A/self → self`, `p.flac ↔ q.flac`) + 1 genuine delete | no hang, no refusal, `swept=1` | PASS |
| ATK-3 | Permissions revoked on all 12 album dirs after batch 1 (600 songs) | `refused(incompleteWalk)`, 600/600/600 | PASS |
| ATK-4 | Volume swapped mid-walk (X detached, same-named Y attached, same folder layout) | `refused(differentVolume)`, X's user data intact, **but** the walk committed Y's files before the end-of-walk check: 3 runs gave +81 / +120 / +0 foreign rows, and 39 / 0 / 120 of X's rows **move-matched onto Y's files** (signatures collided on the fresh images). When X came back the clean walk restored everything (400/400/400, foreign rows swept) | PASS with follow-up (LOCAL): interim wrong rows |
| ATK-5 | FAT32 and exFAT sticks, same name | both report a volume UUID on macOS (synthesised), bound → `refused(differentVolume)`, 20/20 kept | PASS (the "no UUID" known issue is narrower than stated: FAT/exFAT are protected; network volumes untested) |
| ATK-6a | Startup-disk root; and a drive-bound root whose path is now a stale folder on the startup disk | startup root `volume_uuid NULL`, sweeps a genuine delete (`swept=1`); stale folder → `refused(differentVolume)`, 30/30; drive back → `ok` | PASS: 46c1276 is right (probe: `/`, `/Users/…`, `$TMPDIR`, `/Volumes`, `/System/Volumes/Data` all report `volumeIsRootFileSystem=true` and the Data UUID `F3B6222B…`, so nothing on the startup disk binds, and a bound root found there is refused) |
| **ATK-6b** | **Unbound (pre-v8) root; the first walk after the upgrade finds a same-named other drive** | `ok(seen=3 swept=37)`, X data `rows 3/40`, and those 3 are false move-matches onto Y's files | **FAIL** (FIX-FIRST) |
| **ATK-6c** | **Unbound root, drive away, a stale folder with 2 songs at its path on the startup disk** | `ok(seen=2 swept=30)`, rows/entries/plays 0/30 | **FAIL** (FIX-FIRST) |
| ATK-7 | `restampRoot` with another UUID / nil UUID / same UUID | bind=true, other=false, nil=false, same=true; row unchanged by the refused calls | PASS |
| ATK-8 | Walk cancelled after batch 1, with a pending genuine delete | `CancellationError`, 600 kept; next walk `swept=1` | PASS |
| ATK-9 | The root IS a volume's root (`/Volumes/T7`-style); unplugged (empty mount-point dir remains), then back with 1 delete | away: `refused(differentVolume)`, 20/20; back: `swept=1` | PASS |
| MIG-8 | Stores built at v1…v7 with user rows, opened via the real open path | schema 8, `volume_uuid NULL`, plays `[1,2,3]`, entries `[30,10,20]` intact for every version; first walk `swept=0` | PASS |

## 3. Q3: permanent pause, and do clean walks still reap?

- **The original drive comes back → not stuck.** LIB-02b, LIB-02d, ATK-6a and ATK-9 all walk normally once their own
  drive is back. "Paused" only reflects the last walk (`LibraryModel+Reconcile.swift:149`). The next successful
  reconcile resets it (`:142`), and a mount notification or FSEvents triggers that reconcile.
- **A later clean walk reaps genuine deletes:** yes, `swept=1` after every refusal once the cause is gone (LIB-02a,
  LIB-02d, ATK-8, ATK-9).
- **But a PERMANENTLY unreadable folder freezes reaping for the whole root** (Q3 test, FAIL as a liveness check). One
  empty `chmod 000` folder named `#recycle` (a Synology recycle bin the user's account may not open; any folder the app
  may not read) makes every walk `refused(incompleteWalk)` forever. A deleted song is never removed (3 walks: still 5
  rows for 4 files). It also compounds: the reconcile runs the metadata pass only on success (`LibraryModel+Reconcile.swift:141`),
  so songs newly copied into that root stay untagged until the next launch's resume pass. Not data loss, but a
  silent, permanent regression for such roots (the refusal is only logged). Follow-up: **scoped evidence**. The
  `errorHandler` receives the failing URL, so keep only the rows under the folders that errored (and the unreadable files),
  and sweep the rest; run the metadata pass for upserted rows even when the sweep is refused.

## 4. Design and tests (Q4)

- **One typed refusal path: yes.** `SweepRefusal` with 4 reasons, built by one helper in `scan` (`refusal(_:)`) at its 3
  throw sites. The app has one catch arm per walk kind (`performReconcile`, `performAddWalk`); the old
  `RootUnreachableError` and the app-side reachability precheck/restamp are deleted. Minor: the add-walk arm doesn't set
  `reconcileState = .paused` the way the reconcile arm does.
- **Hermetic for CI: yes.** `SweepEvidenceTests` and `ChecksSweepEvidence` use the `LibraryScanner(rootIdentity:)` seam
  over temp folders (no mounts, no sleeps), and the chmod cases are gated `getuid() != 0`. The seam means the real
  failure mechanics (enumerator errors and `lstat` failures when a drive actually goes away) are not exercised in CI.
  My dmg runs cover them and they hold. `volumeWithoutUUIDKeepsTodaysBehaviour` pins the unprotected behaviour for
  unbound roots. That is the ATK-6 gap, and it changes with the fix below.

## 5. The FIX-FIRST item

**Failing cases:** `P5aFixBreakTests/unboundFirstWalk` (ATK-6b) and `P5aFixBreakTests/unboundStaleFolder` (ATK-6c).

**Repro (ATK-6b):**
1. Root on drive X (40 songs, all in a playlist, all played).
2. Set `folders.volume_uuid = NULL` (= any store just migrated v7 → v8).
3. Unplug X; mount a same-named drive Y with 3 other songs at the same path.
4. Run one reconcile.
5. Result: `ok(seen=3 swept=37)`, and the root is now bound to **Y**. When X returns it is refused as
   `differentVolume` forever, until the user removes and re-adds the folder.

ATK-6c is the same with the drive simply away and a stale `/Volumes/<name>/Music` folder holding 2 songs on the startup
disk: `swept=30`, all user data gone.

**Root cause:** `restampRoot` binds an unbound root to whatever is at its path *before* the walk
(`LibraryScanner.swift:105`), and an unbound root has no other evidence check. A root whose path is on the startup disk
or on a no-UUID volume stays unbound and is never checked.

**Fix (S, low risk), either half alone closes both cases:**
1. **Corroborate before binding or sweeping.** A walk that would sweep must have seen at least one of the root's existing
   rows *at its own URL* (unchanged or modified, not move-matched). If `preCount > 0` and none was seen, refuse with a new
   reason (`.noOverlap`) and do not bind. This also covers no-UUID volumes and the "every song replaced" corner. The
   upsert path already classifies; return that count from `upsertReconciling`.
2. **Bind after the walk, not before**, and only on a corroborated walk. A wrong drive then never becomes the bound one.

Add ATK-6b and ATK-6c (seam versions are enough: an unbound root plus an identity with another or nil UUID and
foreign files) to `SweepEvidenceTests`.

## 6. Follow-ups after R1 (not blocking)

1. **Q3 scoped evidence** (above): a permanent unreadable folder must not freeze reaping, or tag reading, for the whole
   root. Surface the refusal in the UI, not only in the log.
2. **ATK-4 interim rows:** re-check the root identity before each batch commit (stop at most one batch after a swap),
   and put the volume UUID in the move-match signature. That prevents the transient foreign rows and the 39–120 false
   relocations seen while a swapped drive is mounted.
3. Known-issues text: FAT32/exFAT report UUIDs on macOS 26 (synthesised), so "some network volumes" is the accurate
   scope. Also document the unbound-root window if fix half 1 is deferred.
