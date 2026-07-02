# Known Issues

Tracked defects surfaced by tests/review that are not yet fixed. Each entry names
the guarding test (kept green via `withKnownIssue` where applicable) so the issue
auto-alerts when the underlying behavior changes.

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
