# Known Issues

Tracked defects surfaced by tests/review that are not yet fixed. Each entry names
the guarding test (kept green via `withKnownIssue` where applicable) so the issue
auto-alerts when the underlying behavior changes.

---

## SEQ-1 — Hard sequencing gates before S9/S10 playlists ship (library data integrity)

**Status:** CLOSED (both gates landed). Surfaced by the S6 full-team review (E1/E2). Gate 2 closed
with S8.4 (move-match); **Gate 1 closed with S10.1** (the `playlist_entries` filter). Kept here as
the record of why the sequencing mattered.

**Verified current state (2026-07-03):** `removeRoot` (LibraryStore+DAO) already implements the
design §8 detach-to-loose flow correctly — it deletes the `folders` row (the `folder_id … ON DELETE
SET NULL` FK detaches the folder's tracks to loose), then deletes only the *unreferenced* ones. The
loose-file path is wired (nullable `folder_id`, `addLooseFile`, and VerifyLibraryStore FS-4 proves a
loose track survives an unrelated root's removal). No code change was needed for E1.

**Gate 1 — `unreferencedTrackIDs` playlist filter — CLOSED (S10.1).** `unreferencedTrackIDs` now
filters candidates against `SELECT DISTINCT track_id FROM playlist_entries`, so `removeRoot` spares
any playlist-referenced track (it detaches to loose, `folder_id → NULL`, entries + FTS rows intact)
and deletes only the genuinely-unreferenced ones. Proven by `VerifyLibraryStore` `pl-gate1-*` checks
(referenced-kept + unreferenced-swept). (Table named `playlist_entries`, not the earlier
`playlist_tracks` sketch.)

**Gate 2 — S8.4 id-preserving move-match — CLOSED (landed on `main`).** A filesystem move reconciles as an id-preserving move (signature match on `(dev,inode,size,mtime)` + format), keeping `tracks.id` and durable user-state (play_count/loved/rating). Proven by `VerifyLibraryStore` move checks (`LibraryStore+MoveMatch.swift`); this is now code truth, not a doc claim. **Known limitation (still forward):** a copy-then-delete move (cross-volume drag, rsync) gets a new inode and is NOT matched (id lost) — `content_hash` is the deferred escape hatch. Traces to EP-LIBRARY (US-LIB move-in-place) + EP-PLAYLIST in [backlog.md](backlog.md). **Both gates are now closed.**

---

## DUR-1 — Playlist durability across schema change (⚠️ HARD GATE before R1)

**Status:** OPEN (deferred by founder decision — S10.1 design §0.1; keep it simple pre-release).

The store keeps `eraseDatabaseOnSchemaChange = true` (the rebuildable-cache "drop-and-recreate on
schema change" discipline). That is correct for the track/album **cache** but **playlists are
user-authored data that cannot be rebuilt from the filesystem.** Two failure modes once real users
have playlists: (a) a schema change **erases** them; (b) worse, a full rebuild **reassigns
`tracks.id` in scan order**, so surviving `playlist_entries.track_id` would point at the **wrong
song** — silent corruption. Harmless pre-release (no real playlists yet), which is why S10.1 ships
with it deferred.

**⚠️ HARD GATE — MUST be resolved before Release R1 ships playlists to users.** The likely fix
(from the S10.1 design + gate): a real additive migration posture + `eraseDatabaseOnSchemaChange`
off in release (dev keeps a `make reset-db`), plus a migration-immutability guard so an edited
shipped migration can't silently corrupt. Revisit as its own scoped task before R1.

---

## ENH-002 — UI loudness readout meter is L/R-only for >2-channel device output

**Status:** OPEN (enhancement; UI-only, low priority). Surfaced by the S6 full-team review (MC-1).

The Now-Playing loudness meter (`AudioEngineBridge+Graph.installMixerTap` →
`loudnessMeterAddStereo`) measures only L/R of the mixer-output bus. It is **correct for the
common stereo device width** (M == 2 → L/R is every channel) and is a **UI readout only** — it does
**not** drive makeup gain. The audible loudness normalization is the DSP kernel's own
N-channel-weighted `LoudnessModule` (S1/S2), which is unaffected.

For a >2-channel **device** output the integrated LUFS shown reads slightly low (surround energy
unmeasured). A correct N-channel UI meter needs the device-width BS.1770-5 weights (surround ×1.41,
LFE excluded — the `LufsMeter` already supports this via `configureChannels` + `addNonInterleaved`)
configured once at tap install and all M planar channels fed in the tap. Deferred with the
multichannel-output path (the S4 binaural fold is deferred) rather than plumb channel-layout weights
into the RT tap for a path that is not yet primary.

---

## ENH-001 — Short-track auto-advance is a reconfigure gap, not a seamless seam

**Status:** OPEN (enhancement, low priority).

*(KI-001 — "the VM stops mid-playlist on short tracks" — was **RESOLVED 2026-07-02**: analysis showed the VM already continues via `tickSpectrum()`'s `playbackEnded → advance to pendingNextIndex` branch; the stale `VM-AA-RTR-1` assertion was corrected to the continue behavior. Founder's continue/advance decision is satisfied. The full triage/panel narration is in git.)*

The short-track advance is a fresh-start reconfigure **gap**, not a gapless seam. Making it seamless for arbitrarily-short tracks needs an engine-side **2-deep on-deck queue** — a single on-deck slot can't arm track C until track B is current at the seam, and B may be shorter than the arm latency + the 20 Hz poll interval. Scheduled against the gapless backlog (US-PLAY-08 lineage); low priority (only tiny tracks; fallback is a brief gap, not a stop). Guarded by `VM-AA-RTR-1` (`withKnownIssue` — fails when fixed, prompting a proper assertion).
