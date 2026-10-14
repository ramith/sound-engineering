# P5a re-check: 5dcad34 ("an unbound folder is walked only where its songs are, and bound only after a walk confirms its drive")

I ran everything in my own worktree `.claude/worktrees/panel-p5a`, detached at 5dcad34, against the real scanner and store, on
temp dirs and real APFS / FAT32 / exFAT disk images. Every image was detached, and `mount | grep p5a-` = 0 at the end.
Two images were left mounted by a harness bug of mine mid-run (a test without a `defer` detach); I detached them and fixed
the harness. Nothing touched the founder's library, and the app was never launched.

Tests (uncommitted, copies in `exp-p5a/`): `P5aFixBreakTests.swift` and `P5aRecheckTests.swift`. Log: `exp-p5a/recheck-run1.log`.
The fix's own suites pass (25 tests), and VerifyLibraryStore passes 161/161 (exit 0, `exp-p5a/vls-recheck.log`).

## Verdict: SHIP. The FIX-FIRST item is closed and nothing regressed. Two follow-ups before real users switch drives (§4).

## 1. The FIX-FIRST cases now hold

| Case | 46c1276 | 5dcad34 |
|---|---|---|
| ATK-6b: unbound root, same-named other drive at the first walk after the upgrade | swept 37/40, 3 false move-matches, bound to the wrong drive | `refused(unrecognizedFolder)`, 40/40/40 kept, **still unbound**, no foreign rows. The right drive returns with 1 genuine delete: `ok(swept=1)` and **binds to X's UUID** |
| ATK-6c: unbound root, drive away, stale folder with 2 songs on the startup disk | swept 30/30, all user data gone | `refused(unrecognizedFolder)`, 30/30 kept, unbound. The drive returns: `ok`, binds to X |

## 2. No regression

| Case | Result at 5dcad34 |
|---|---|
| LIB-02a, `chmod 000` / `444` subfolder | `refused(incompleteWalk)`, 10/10/10; after restore + 1 delete: `swept=1` |
| LIB-02b, 800 songs, volume detached mid-walk | `refused(rootVanished)`, 800/800/800, no extra rows; remount: `ok(seen=800 swept=0)` |
| LIB-02d, same-named other drive (bound root) | `refused(differentVolume)`, 60/60/60; X back + 1 delete: `swept=1` |
| Genuine-delete control | swept exactly 1, every time |
| ATK-1, error at the root / 5 deep | refused, 6/6 |
| ATK-2, symlink loops | no hang, `swept=1` |
| ATK-3, permissions revoked mid-walk (600 songs) | refused, 600/600/600 |
| ATK-5, FAT32 / exFAT same-name swap | both report a UUID, both bound, `refused(differentVolume)`, 20/20 |
| ATK-6a, startup disk | a startup-disk root now binds as the sentinel `"startup-disk"` (stable across Macs); it still sweeps a genuine delete; a drive-bound root whose path is a stale startup-disk folder is refused; the drive returns → `ok` |
| ATK-7 `restampRoot` | the other / nil drive is refused and changes nothing; same drive refreshes |
| ATK-8, cancelled walk | `CancellationError`, 600 kept; next walk `swept=1` |
| ATK-9, root = the volume's root | away: refused, 20/20; back + 1 delete: `swept=1` |
| MIG-8, upgrade from v1…v7 | schema 8, `volume_uuid NULL`, plays and playlist entries intact, first walk `swept=0` (on its own drive it binds) |

(The first combined run showed two failures in LIB-02b and FAT32. Both were my harness: a shared static store path
raced across parallel suites. Fixed; both pass when re-run.)

## 3. New angles from the new rule

| # | Angle | Result | Verdict |
|---|---|---|---|
| RC-a | Unbound root; every song deleted and 3 new ones copied in | `refused(unrecognizedFolder)` on every walk; **the 3 new songs never reach the library**; old rows kept. Bound: `ok(swept=5)`, 3 added | Stuck while unbound (documented in known-issues). Exposure: the one-time window after the upgrade, plus volumes with no UUID |
| RC-b | Unbound root; the one subfolder holding every song renamed | `refused(unrecognizedFolder)`, never walked. Bound: move-match keeps every id | The same: stuck while unbound (documented) |
| RC-c | Brand-new empty folder, then songs copied in | first walk `ok(seen=0)`, binds `startup-disk`; second walk adds 4 | PASS |
| RC-d | Unbound first walk, only 3 of 40 songs remain (genuine) | `ok(swept=37)`, binds | PASS (holds-any-song is the right evidence) |
| **RC-e** | Unbound window; a same-named **backup** drive holding 30 of the 40 songs at the same paths (an older copy of the library) | Y is recognized (it holds songs where the library has them) → walked → **swept 10** (the songs added since the backup, with their playlist entries and plays) → **bound to Y**. X returns: `refused(differentVolume)` forever | **Residual data loss** (narrow): needs the one-time unbound window plus a same-named backup at the first walk. Not blocking; see §4 |
| RC-f | Volume swapped mid-walk (3 runs) | the per-batch identity check stops the walk: **0 foreign rows, 0 false relocations** in 3/3 runs (46c1276: +81/+120 foreign rows, up to 120 relocations); X's data 400/400/400 | PASS: the per-batch check works |
| — | Add-walk vs reconcile catch arms | both call `pause(refusedBy:in:)`; the add walk now also sets `walkedState` on success | PASS, aligned |

## 4. The documented remedy is lossy (RC-g): follow-up, high priority

`known-issues.md` LIB-VOL-1 tells the user that a paused folder (a replaced same-named drive, an unbound folder whose
songs all moved, or RC-e's wrong binding) "stays paused until the user removes and re-adds the folder". RC-g ran exactly
that with the real store: 4 songs, 2 of them in a playlist, all with plays=7 and loved=true → `removeRoot` → `addRoot`
+ walk. The 2 playlist songs kept their ids, plays and loved. **The 2 songs in no playlist came back with new ids,
plays=0, loved=false.** `removeRoot` deletes every row no user playlist references, and their user state goes with
them.

That matters more now. Before the fix, a same-named replacement drive holding the same library (a clone onto a bigger
"T7", which is common) simply worked, because rows are keyed by URL. Now it is refused forever as `differentVolume`, and
the only documented way out resets the play history of every song not in a playlist.

**Recommendation (S, next release; before telling any user to remove/re-add):** a lossless **"Use this drive"** action
on a paused folder. The user confirms, and `restampRoot` is called with the new identity (rebind), followed by a normal
walk. In the meantime, add one sentence to LIB-VOL-1 warning that remove + re-add resets play counts, loved flags and
ratings of songs that are not in a playlist. The same action also resolves RC-a, RC-b and RC-e (rebind to the right drive).

## 5. Other follow-ups (unchanged, not blocking)

- **RC-e hardening (optional):** an unbound root's "holds its songs" probe could require a song whose `(size, mtime)`
  matches the stored row. That doesn't help a backup that preserved mtimes; requiring the stored `inode` would, but it
  would mark a re-copied library unrecognized. Given the one-time window, I'd leave the rule and ship the rebind action.
- **Q3:** still open (documented): a permanently unreadable folder in a root means its deleted songs are never swept,
  and a refused reconcile skips the tag pass. Scope the evidence to the failing subtree (the `errorHandler` URL) and
  surface "paused" in the UI.
