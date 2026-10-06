# S10.8 part 1 — Realigned Target implementation ledger

Implementation record for the PR-A..G wave against
[docs/design/now-playing-realigned/](../design/now-playing-realigned/README.md).
Every PR: built, `strict-gate` green, launch-smoked, committed on `sprint/s10-8-polish`.
**Founder verification cells are OPEN** — no screenshot capability in the implementing
session (Screen Recording TCC absent); every ☐ below is the founder's dark+light+RM pass.

| PR | Commit | Scope | Founder cells |
|---|---|---|---|
| A | `1601310` (pre-package) + `31fcf94` (package landed) | zero-risk batch + package/docs | ☐ |
| B | `7ecc170` + `838da19` | capsule tab strip, pill chevron, onAccent flip | ☐ dark ☐ light ☐ hover ☐ VO |
| C | `e1d3eb7` + `a5799c9` | one-row queue header, chips, hover grips | ☐ dark ☐ light ☐ drag-reorder ☐ filter |
| D | `a590b50` | playing-row card + mini equalizer | ☐ playing ☐ paused ☐ RM |
| E1 | `4918ae3` | floating card + glow + slim carved recipe | ☐ hug ☐ min-window scroll ☐ light |
| E2 | `2378f30` | TRUE-peak meter (kernel extraction) + meter rows | ☐ meters ☐ amber >−1 dBTP |
| F | `c52deab` | two hero chips, pulsing dot | ☐ states: pure/enhanced/XF/fallback/interrupted |
| G | `6968a1b` | styled-glass bands, play gloss, pulsing footer dot | ☐ both bars both appearances ☐ RT |

## Deliberate deviations from the package (each needs founder OK or a follow-up)

1. **PR-A adaptation** — tokens did NOT land as one up-front PR: the repo's
   hostile-Periphery staging rule (tokens land with their first consumer) made the guide's
   "PR-A adds all tokens" un-gateable. Each token landed in its consuming PR, all through
   `Palette` + the R4 audit (never `Color(hex:)` view-side — the guide's samples predate
   the S10.7 Kit).
2. **onAccent** flipped white → #0C1413 app-wide (logo/play/tab glyphs) — realigned
   identity AND retires the flagged 2.5:1. Play-overlay glyphs in Library grids changed too.
3. **Device pill width 302, not the guide's ~240** — the founder-fixed no-truncation
   posture from the deviations audit is newer than the mock's estimate (288 + 14pt for the
   PR-B chevron, founder round 1).
4. **Jump-to-now-playing chip kept** as a 4th header icon (mock shows 3) — function
   preservation; and the queue filter pill shows in Up Next only (a Recently-Played filter
   would be new function).
5. **Mini equalizer is sine-driven** (the package's spec) — REVERSES the earlier
   "real spectrumBars, not a sine loop" mandate; recorded in the plan §B.
6. **Inspector card radius stays 22** (mock: 18) — TOK-01's concentric chain (panel ≥
   lens 20) + the shipped S10.7 tune. Founder may retune both radii together.
7. **Card shadow/rim keep the S10.7 founder-tuned values** (mock: shadow 25/18, rim 13%) —
   same family, deliberately not re-tuned without eyes on screen.
8. **Carved knob stays 14pt shared** (guide wants 15pt inspector / 13pt scrubber) — one
   shared primitive beats a 2pt fork; groove is 4pt/13% per the mock.
9. **Amber** — meterHot #F0B429 landed as a NEW audited pair (dark) with a #B45309 light
   fill + statusWarningText-derived light text. Three amber family members now exist, each
   with one duty (statusWarning dot/badge, statusWarningText text, meterHot meter).
10. **CLIP word retired** with the sample-peak bar; the hot state's cues are the amber
    tail/value, a **▲ glyph prefixing the value** (the visible non-color cue — restored at
    the break-it round, A-M5), and the spoken "above the −1 dBTP ceiling".
11. **Hero format·rate chip text is primary label**, not the mock's white-60% —
    R4-BADGE-01's standing rule (dimmed hierarchy on a chip over the teal core fails AA).
12. **Bands: light appearance keeps plain window + hairlines** (sheen is dark-only per
    grammar rule 6); the mock's light toolbar PNG shows the dark track only — the band
    sheen itself has no light-side spec.
13. **True peak is 8× ISP** (guide says 4×) — the meter reuses the limiter's
    oracle-verified 8× kernel; more accurate than asked.
14. **Inspector uses the Regime-B fill at 72%** (guide offered "real material OR the
    repo's existing glass recipe") — founder decision 2 (fill strata, not blur) applied.

## Verified by machine (per PR)

- R4 audits grew with every color: R4-TAB-01, R4-CHIP-01/02, R4-ROW-01, R4-METER-01 —
  all sampled against the real glow-field composites where the surface can sit there.
- TOK-04 extended to controlActiveFill; rowNowPlaying retune asserted at 13%.
- LAY-01/02 re-verified with inspectorWidth 320.
- C++: `Loudness_TruePeakKernel_InterSample` (fs/4 +45° sine recovers −6.02 dBTP ±0.35
  where sample-peak under-reads 3 dB); limiter oracle (libebur128) still green through
  the extracted kernel — the break-it round additionally verified the delegation is
  LINE-IDENTICAL math and the golden-master hash unchanged (0xe7267654ba01d315).

## Break-it round (2 reviewers: SwiftUI SME + adversarial QA) — all fixed same day

1. QueueIconButton's 28pt chip wasn't clickable outside its 12pt glyph (frame/background
   outside the Button never extend its hit region) → chip rebuilt inside the label.
2. Queue header overflowed the 508pt minimum queue column worst-case → chips + switcher
   `fixedSize()` (control labels never truncate), count subtitle = designated victim,
   filter min 110 → 90.
3. No Dynamic-Type headroom in the new header/badge (fixed 32/28/20/18pt frames) →
   @ScaledMetric throughout (the tab strip's own pattern); FormatBadgeView radius follows.
4. True-peak row was gated on the INTEGRATED-LUFS gate (≥400 ms of blocks) — a hot
   transient at track start would be suppressed exactly when it matters → row keys on its
   own −110 dB floor.
5. An active filter silently survived queue-emptying (next queue arrived pre-narrowed,
   reorder disabled) → emptying the queue clears the filter.
6. Footer Pure-fallback state: amber warning dot beside teal "Enhanced" read as two
   states → neutral label under fallback.
7. Visible non-color hot cue restored (▲ prefix — deviation 10 above).
8. Deprecated `foregroundColor` in new code → `foregroundStyle`; inert scrubber
   play↔pause ease removed (erased style TYPES can't interpolate) with an honest comment.
9. Mono tap path did 2× redundant ISP work → single-channel loop.
10. NEW `Loudness_MeterBridge_TruePeak`: the C-ABI bridge end-to-end (multi-buffer
    history continuity, MONO aliasing, dBTP mapping) — the harness now compiles
    LoudnessMeterBridge.cpp; 122 passed / 0 failed (1 pre-existing PENDING).

## Founder round 1 (2026-07-19, live screenshot)

- **Tab strip → RIGHT edge** of the chrome (mock `png/00`: logo + pill left, spacer, tabs
  right; the implementation had kept the old left-packed order) — FIXED.
- **Device pill re-truncated** ("MacBook Pro Spe…"): the PR-B chevron ate ~14pt of the
  name area inside the fixed 288pt pill — the same squeeze class as the PR-6 rate slot.
  Width 288 → 302 absorbs it — FIXED.
- Otherwise the screenshot matches the target (hero chips incl. the live "-- kHz" empty
  slot, one-row queue header, playing-row card + still bars, floating inspector with
  meters at "—" while idle, styled bands, glossy play). Remaining cells still open.

## Founder round 2 (2026-10-06, live screenshots)

First founder look after the ~2.5-month gap, during the Library's own round 1 (see the
[library ledger](s10-8-library-ledger.md) for the seven Library/chrome fixes — three of which
change Now Playing too: the device pill is now one live menu label that hugs its content, and
the footer keeps a stopped track's artist + cover). Two Now Playing findings, both approved by
the founder and FIXED:

- **Queue titles sat above the row's centre line.** The row's second line renders
  `AudioFile.relativePath`, which is EMPTY for every track (all `AudioFile`s come from the
  library adapter) — and an empty `Text` still claims a line. The number, format tag and time
  were centred; the title was not; each row was a line taller than the mock's. Now the second
  line appears only when there is a path; the row card is 34pt with a 2pt seam (the mock's
  36pt pitch, `png/00` / `png/04`; was 40). The path stays on the row tooltip. The adapter's
  own doc comment had recorded this as known debt.
- **The inspector card had a bright band along its bottom edge** — the 8a bottom light bleed,
  which the Realigned Target's card does not have (`png/00` reads (27,29,34) to its last pixel
  row). It was also a contrast hazard: tertiary text resting on it measured 4.18 (break-it
  R4), which had been fenced off with a bottom inset equal to the bleed height. The floating
  card is now flat on both screens (`SurfaceRole.hasBottomBleed`, RES-05); the inset is plain
  spacing.

**Founder decision — the analyzer lens keeps its bleed.** The lens carries the same bottom
band and the mock's lens is flat there too, but the founder reviewed it on screen and said the
spectrum analyser is fine as it is (2026-10-06). So `lens` (and `badge`) stay
`hasBottomBleed == true` deliberately — do not "finish the job" by flattening them.

**Verified on the founder's screenshots by measurement** (not by eye): queue row pitch 36.0pt
(mock 36), playing-row card 34.0pt (mock 34), title-to-time centre offset 0.0pt, inspector fill
flat to its last pixel row, Library rail last-row-centre → card bottom 29.0pt (mock 29; was 44).

**Part 1 CLOSED (founder, 2026-10-06):** "I like the current screen, let's close it." The 14
deliberate deviations above are **accepted as they are**, and the dark founder cells close with
them. The light / Reduce Transparency / Increase Contrast cells move to the glass sweep's
Sprint B (light mode designed once on the shipped screens) —
[s10-8-glass-sweep-plan.md](s10-8-glass-sweep-plan.md).
