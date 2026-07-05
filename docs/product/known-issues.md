# Known Issues

Tracked defects surfaced by tests/review that are not yet fixed. Each entry names
the guarding test (kept green via `withKnownIssue` where applicable) so the issue
auto-alerts when the underlying behavior changes.

---

## SEQ-1 — Hard sequencing gates before S9/S10 playlists ship (library data integrity)

**Status:** OPEN (enforced sequencing constraint, not a defect in current behavior). Surfaced by
the S6 full-team review (E1/E2). Both gates are safe to leave open *only* because no playlist table
or playlist UI exists yet; shipping S9/S10 without closing them causes data loss.

**Verified current state (2026-07-03):** `removeRoot` (LibraryStore+DAO) already implements the
design §8 detach-to-loose flow correctly — it deletes the `folders` row (the `folder_id … ON DELETE
SET NULL` FK detaches the folder's tracks to loose), then deletes only the *unreferenced* ones. The
loose-file path is wired (nullable `folder_id`, `addLooseFile`, and VerifyLibraryStore FS-4 proves a
loose track survives an unrelated root's removal). No code change was needed for E1.

**Gate 1 — `unreferencedTrackIDs` playlist filter (S10).** The hook currently returns ALL
candidates (no `playlist_tracks` table yet), so removing a root deletes every track in that folder.
BEFORE the S10 playlist UI ships it MUST gain `AND id NOT IN (SELECT track_id FROM playlist_tracks)`,
or `removeRoot` will delete playlist-referenced tracks. Marked with a ⚠️ HARD GATE comment at the
call site.

**Gate 2 — S8.4 move-matcher before S9/S10 — ADDRESSED & LANDED on `main` (S8.4 slice 1).** A
filesystem move now reconciles as an
id-PRESERVING move: the scanner's walk uses `upsertReconciling` → `moveCandidate` (matches the
`(dev,inode,size,mtime)` + `format` signature via `idx_tracks_dev_inode`, ambiguity/cross-volume →
no-match) → `moveMatched` (relocate + stamp `last_seen_scan` in one txn, so the end-of-walk sweep
can't reap it). A rename / cross-dir / cross-root move keeps its `tracks.id` AND its durable
user-state (play_count/loved/rating) — proven by VerifyLibraryStore AD–AH (AD reference-survives-move
is the Gate-2 assertion). The signature is now *matched*, not merely *populated*. This has since
landed on `main` (`LibraryStore+MoveMatch.swift`; VerifyLibraryStore AD/AH/AN move checks in
`main.swift`), so Gate 2 is effectively closed. Remaining before S9/S10: close Gate 1 (above). Known
limitation: a copy-then-delete move
(cross-volume drag, rsync) gets a new inode and is NOT matched (id lost) — `content_hash` is the
deferred escape hatch. Traces to EP-LIBRARY (US-LIB move-in-place) + EP-PLAYLIST in docs/product/backlog.md.

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

## KI-001 — Short-track auto-advance: RESOLVED (VM already continues; seamless-for-tiny-tracks tracked as ENH-001)

**Status:** RESOLVED 2026-07-02. Closer code analysis (during the fix) showed the VM does NOT
stop mid-playlist: `tickSpectrum()`'s `playbackEnded → advance to pendingNextIndex` branch
already CONTINUES to the queued next track via a fresh start (a brief reconfigure gap).
`pendingNextIndex` is always set mid-playlist and is nil only at genuine end-of-playlist (the
one case that legitimately stops). The VM-AA-RTR-1 test's old `isPlaying == false` assertion was
STALE (pre-dated the reconfigure-gap branch); it now asserts the correct continue behavior.
Founder decision (continue/advance) is satisfied.

**Remaining as ENH-001 (enhancement, not a defect):** the short-track advance is a fresh-start
reconfigure GAP, not a seamless (gapless) seam. Making it seamless for arbitrarily-short tracks
requires an engine-side **2-deep on-deck queue** — a single on-deck slot cannot arm track C until
track B is current at the seam, and B may be shorter than the arm latency + 20 Hz poll interval.
Scheduled against the gapless backlog (US-PLAY-08 lineage); low priority (only tiny tracks; the
fallback is a brief gap, not a stop).

**Original triage (superseded by the analysis above):**
**Severity:** BA = real user-visible defect class; PM = P2 (narrow race window, clean-stop fallback)
**Surfaced by:** `swift test` — `AutoAdvanceReconfigureGapTests.VM-AA-RTR-1` (resurrected 2026-07-02 when the Testing.framework skew was fixed; the test had never run before)
**Related shipped stories:** US-PLAY-08 (gapless), US-PLAY-09 (auto-advance)

### Symptom
When a track reaches EOF **before** the ViewModel's poll-driven "arm the next track"
step has run (i.e. a very short track — intro, spoken interlude, short classical
movement — racing the ~20 Hz advance poll), the engine reports `endedFlag` with no
next track armed, and the VM does **not** advance. In the mock (which the reviewers
verified mirrors `AudioViewModel+AutoAdvance` logic) this manifests as
`isPlaying == true` with playback effectively stalled rather than advancing to the
next queue entry.

### Panel assessment (2026-07-02 test-validity review)
- **audio-dsp / qa:** the *test* is correctly written — it's a genuine
  behavior gap, not a test bug. It documents current behavior as a regression target.
- **business-analyst:** correct behavior is **continue/advance**; a silent stop
  mid-playlist on short tracks is a real defect for a "bring your own library" app.
- **product-manager:** **P2** — narrow trigger (<~50 ms tracks vs the 20 Hz poll),
  fallback is a clean stop (not a crash/glitch). File against the gapless/auto-advance
  backlog; do not flip the test assertion until the fix ships.

### Open product question (for founder)
What is the desired behavior when a track ends before the next is armed?
(a) pre-arm / engine-side look-ahead so the next track is always ready (continue), or
(b) accept the current stop as intended for this edge. The correct fix location is the
arm-after-start poll design in `AudioViewModel+AutoAdvance.swift` /
`AudioViewModel+SpectrumTimer.swift`.

### Test handling
`VM-AA-RTR-1` is wrapped in Swift Testing's `withKnownIssue` so the suite stays green
while the defect is tracked. When the behavior is fixed, the known issue will stop
reproducing and the test will fail — prompting removal of the wrapper and a proper
assertion of the decided behavior.
