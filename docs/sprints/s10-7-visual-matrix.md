# S10.7 visual matrix — founder screenshot checklist (R6)

> The TEMPLATE lives here (committed once, PR 1b); each PR's FILLED matrix is pasted into its
> PR description with the founder's screenshots attached. The loop: founder screenshots the
> PR's required cells at the milestone → vs-mock/vs-before review of the screenshots → founder
> sign-off comment → merge. A SKIPPED cell is recorded in the ledger below with the house TEMP
> grammar (reason + expiry ≤ sprint end) — tracked debt, never a silent drop; the end-of-sprint
> full A–H grid is the enforcement backstop. Design: [s10-7-liquid-glass-design.md](s10-7-liquid-glass-design.md) §7 R6.

## States

| Cell | State | How to set it |
|---|---|---|
| **A** | dark / default | System Settings → Appearance → Dark |
| **B** | light / default | Appearance → Light — **capture A and B in ONE app run, no relaunch** (makes every PR an implicit H) |
| **C** | dark / Reduce Transparency | Settings → Accessibility → Display → Reduce transparency ON |
| **D** | light / Reduce Transparency | as C, light appearance |
| **E** | dark / Increase Contrast | Accessibility → Display → Increase contrast ON (note: this force-enables Reduce Transparency — E/F verify the IC-specific hairline/border strengthening, not just opacity) |
| **F** | light / Increase Contrast | as E, light appearance |
| **G** | dark / Reduce Motion, while playing | Accessibility → Display → Reduce motion ON; capture during playback (pulse/EQ-bars/caps must be static) |
| **H** | live-toggle mid-playback | flip appearance dark↔light AND Reduce Transparency on↔off while playing, on the visible tab — catches cached-resolution bugs no static check can see |

## Required cells per PR

| PR | Cells | Extra checks |
|---|---|---|
| 1a | A, B (single run) — assert NO visual change | 3 forced-visible overlay cells in A, B, C: error banner (kill the output device), queue toast (add album → queue from Library), EQ recall banner (switch device on EQ tab); one-off before/after pixel diff |
| 1b | A, B — no visual change (onAccent IS white) | gate green; dry-run counts pinned in PR body |
| 2 | A, B, C, D, H — **vs the 8a mock** | band-seam glow clipping; wide-gamut banding; base-compat micro-pass over the other four tabs (dark) |
| 3 | A, B, C, G | caps freeze on pause; G: no cap animation; **Instruments row** (recipe below) |
| 4 | A, B, E, G | long-title truncation cell; all four signal-path badge states |
| 5 | A, B, C, E, H | 880×640-min cell (default + max type size); inspector-scroll cell; **VO/keyboard script** (below); Instruments row |
| 6 | A, B, E, H | window-drag-on-chrome cell (L2); system-surfaces cell (device menu + a context menu render true glass over our bands) |
| 7 | A, B, H | track-change glow transition (Reduce Motion: cut, not crossfade); worst-case album art set (near-black, neon, low-chroma covers); missing-art fallback |
| END | full A–H on the finished tab | §10 break-it list; rig retro (rules fired / false-positives; TEMP suppressions re-dated or resolved) |

## R5 — Instruments recipe (PR 3, PR 5, sprint end)

`make run` → play a 96 kHz track → Now Playing tab, dark mode → attach Instruments
"Core Animation FPS" (or Metal System Trace) to AdaptiveSound → 60 s steady watching +
30 s window-resize + tab-flips while playing. Budget: **zero SUSTAINED dropped frames** at the
display refresh (120 Hz ProMotion / 60 Hz external); GPU frame time p95 < ~50% budget;
one-frame blips on tab switch acceptable. Record the observed number in the PR's matrix block.

## PR 5 — VO/keyboard traversal script (manual, once per PR-5 revision)

**Prerequisite: System Settings → Keyboard → Keyboard navigation ON** — the custom
`.focusable()` views (lens + both sliders) join Tab traversal only with it on; without it
the walk fails for the wrong reason.

Expected traversal: hero (title group) → lens frame ("Spectrum analyzer", carries the
"Open Monitoring" accessibility action + keyboard activation) → queue (first focus via
`.defaultFocus`; ↑/↓/Return work) → inspector: gain slider → intensity slider → meters →
crossfeed toggle — each slider focusable with VISIBLE focus ring, ←/→ adjusts by one step,
VoiceOver announces label + value and supports adjustable. Footer transport reachable after
the tab content. A keyboard user who can reach but not OPERATE a control = PR failure.
Lens activation is **Return** (Space is the transport toggle app-wide — by design); if Return
on the focused lens does NOT open Monitoring, report it — that's the one genuinely uncertain
macOS behavior here, and we'll wire it differently.

## PR 5 — review-fix verification riders (check during the founder round)

The swiftui-pro round (fixes in `bbf36cb`) added targeted riders to the standard cells:

1. **Jump-vs-filter (was BLOCKER):** with the now-playing track filtered OUT, and again from
   the No-Matches state, press Jump-to-Now-Playing — the filter must clear AND the row must
   scroll-center (both halves, not just the clear).
2. **Escape's landing:** Escape while editing the filter clears it and ↑/↓ work IMMEDIATELY
   (focus hands to the queue, never strands).
3. **Gain-knob grab:** grab the knob at min and at max without moving — the value must NOT
   jump on mouse-down (live-commit audio control).
4. **Hero badges:** bits/decoder capsules are GONE from the hero (rate/path/intensity/XF
   remain); they live only in the inspector's signal-detail line.
5. **Inspector corners:** while scrolled mid-content, nothing pokes square through the
   radius-22 top/bottom corners.
6. **Grip-while-filtered:** the drag grip disappears when the filter narrows the list
   (context-menu moves still work); it returns when cleared.
7. **Diacritics:** filter "beyonce"-style queries match accented titles if the library has
   any (else skip).

## Ledger

### PR 7 — accepted 2026-07-18 (final milestone)

Art-sampled glows, D8 (`6ccd5a1` + review round `53e431b`). swiftui-pro verdict was
request-changes; all findings applied — including the cache-key BLOCKER (relativePath is ""
for every queue track → the first palette would have served the whole session; keyed by the
file URL now) and a strengthened audit: R4-GLOW-D8 folds the FULL 2³ per-slot {clamp-corner,
brand} lattice (the review's single extra fold under-covered brand-blue fallbacks), plus the
panel⊕field pairs. Clamp floors now judge the SCALED color; loose-file art decodes capped at
512px.

Founder round: the first test track ("Sunn Raha Hai") exposed a perception trap, not a bug —
the cover is teal-orange graded, so its sampled palette ≈ brand teal. DB-driven probe of the
REAL artwork verified the pipeline (426/576 pixels vote → teal palette); probing all 43
library covers: 41 sample, 2 brand-fallback by design (too dark / achromatic). A 6-track
demo queue (rose/magenta/gold/red/blue covers, picked by probe) then showed per-track
recolor unmistakably. Founder: "ok I see what you meant it changes." ACCEPTED.

Riders on the sprint-end A–H pass (not re-verified separately): B light no-change, H live
flip with a sampled palette active, missing-art brand fallback, crossfade-vs-flicker feel
(the resolve-gap brand dip), Reduce-Motion cut.

### PR 6 — accepted 2026-07-18

Chrome + footer restyle (`b78b3ad..11bf514`): Enhanced sample-rate fix (the founder's
`-- kHz` finding), status text/fill split (founder decision; retired ALL 4 contrast pins —
`swift test` = 0 known issues since), glass device pill + D5 rate readout w/ numericText,
footer scrubber on the shared carved groove (shadow-literal TEMP retired by adoption),
ChromeBar Dynamic-Type clamp + gate guard, footer signal slot widened (SLOT-03).

Founder rounds (3): caught the stale-binary trap, the footer "48 k…" truncation (fixed,
SLOT-03), the pill readout never rendering (macOS Menu labels don't re-render on data
change — readout moved beside the Menu, `030b6ad`), and the WRONG-SONG bug (device switch /
48 kHz seek fired stale .dataPlayedBack completions into the armed gapless seam → epoch
guard `92aef6b` + review hardening `11bf514`; swift-expert verdict APPROVE with the
stale-session hole closed). Founder verified: pill rate rolls on device switch; scrubber
"looks ok"; H clean — the light-mode teal play button is BY DESIGN (brand-gradient primary
action, matches the logo + the 8a mock; prev/next correctly flip neutral); device switching
now keeps the same song.

Cells: A (dark, playing — pill + footer readouts live), B (light), H (live flip), inspector
closeup (gain max + intensity 100%), light error banner (see below).

Retired / relocated cells:
- CLIP/statusError visual cell — RETIRED BY DESIGN RATIONALE: the Sprint-4 limiter enforces
  a −1 dBTP ceiling and `isHot` fires at ≥ −1 dBFS, so red/CLIP is unreachable in normal
  Enhanced playback (the founder pushed gain+intensity to max — bar pegged, never red).
  The state is the safety-chain tripwire; light-mode legibility is proven by R4-LEG-03 math.
- error-banner LIGHT cell (deferred since PR 1a) — CAPTURED this round ("Playback failed …
  error 0" over light UI; statusWarningText dark-amber glyph rendering correctly).
- 42pt chrome-clamp cell — DEFERRED to the sprint-end pass: content type-scaling was proven
  in the PR-5 round; the clamp is gate-asserted (`clamped_bands`); the founder's Text size
  is stuck in a per-app "Custom" state that doesn't apply system-wide (a Settings-side
  issue, not app code). Founder: "maybe that's ok".

Break-it-round items filed from this PR's rounds:
1. error 0 (`engineNotInitialized`) after a BT disconnect → play (founder repro; pre-existing
   engine-lifecycle race — avEngine/playerNode nil at play; only teardown nils them).
2. Seam-review MINOR-2: capture-vs-schedule sub-ms window (transport vs config-change
   overlap family — pre-existing, strictly improved by the epoch guard).
3. Seam-review NIT-5: consider a headless decision-table test for the epoch-guard bumps.
4. Seam-review NIT-6: pre-existing end-of-queue sentinel question — verify the
   "playbackEnded — no next track, stopping" log fires at end-of-queue with repeat off.
5. Scrub + natural-track-end riders: founder verified device switching; scrubbing and the
   natural gapless ending are covered by the review's no-behavior-change proof — re-exercise
   both explicitly in the break-it round.

### PR 5 — accepted 2026-07-18

The 8a restructure (hero-right lens, queue-flex + 260pt inspector, queue filter) + the
swiftui-pro review round (`bbf36cb`) + the crossfeed one-row fix (`67a25ee`).

Cells captured (dark unless noted): A (playing — hero-left short badge set + lens at 560max
with 0 dB/axis/gridlines/caps; queue rows directly on the glow; both carved sliders), B
(light — white-glass grammar), C (Reduce Transparency — glow field suppressed to flat base,
lens/inspector/badges all opaque; the resolver's RT→opaque swap verified LIVE), E (Increase
Contrast — opaque + visibly STRONGER hairlines around lens/inspector/every badge, the
glassHairline HC variant confirmed), H (live dark↔light toggle — both directions re-resolve
clean), min-window (~880×668 true minimum — native titlebar adds ~28pt outside the enforced
880×640 CONTENT; six queue rows + full inspector + no truncation) at default AND 42pt text
(hero grows + tail-truncates, badge row scales without clipping, queue full).

Keyboard/VO walk (keyboard-nav ON) — all green:
1. Return on the focused lens OPENS Monitoring (the one behavior reading couldn't prove).
2. Jump-to-Now-Playing with the playing track filtered OUT: clears the filter AND scrolls.
3. Escape in the filter: clears + ↑/↓ move the queue immediately (focus handed back).
4. Grab the gain knob at min/max without dragging: value does NOT jump on mouse-down.
5. Focused sliders: ←/→ step the value one increment.

Review-fix riders all verified: no bits/decoder capsules in the hero; grip behaviour and
inspector corners hold. Founder change during the round: crossfeed toggle + strength picker
now share one inspector row (`67a25ee`).

Findings routed to PR 6 (that PR owns the surface, not a PR-5 defect):
- The signal badge + footer show `-- kHz` under Enhanced — `achievedSampleRate` is populated
  only by the Pure-mode path; Enhanced leaves it 0. PR 6 (D5 sample-rate readout) wires the
  Enhanced rate and adds the footer slot to SlotFitTests.

### PR 3 — accepted 2026-07-17

Cells captured: A (dark, playing — lens + caps read as an instrument), B (light — white-glass
lens), C (dark + RT: glow field suppressed to the flat base AND the lens went opaque — the
resolver verified LIVE), D (light + RT: opaque lens), G (RM on — bars/caps render, data-driven).
Review finding applied post-capture: the light lens SHADOW was too heavy (0.30 @ 18 read as a
smudge) → tuned to 0.15 @ 12 / y 5; PR-4's B cell re-verifies.

Deferred (TEMP, expiry = sprint end 2026-08-15):
- Instruments row — reason="parked by the founder; any track works for the FPS pass (96 kHz was
  the stress suggestion, not a requirement)"

### PR 2 — accepted 2026-07-17 (glow tokens FROZEN per the §8 stopping rule)

Round 1: founder screenshots A (dark, all five tabs) + B (light, unchanged as designed) —
deep base verified app-wide, other tabs readable (material-plate pop pre-briefed); glow field
correct but under-covered → founder decision: PROPORTIONAL sizing (mock's coverage fractions).
Round 2: coverage matches the mock's ambient wash — ACCEPTED. Geometry/alphas frozen; only an
R4 failure may reopen them.

Deferred cells (TEMP, expiry = sprint end 2026-08-15):
- C/D (Reduce Transparency dark/light) — reason="not captured; RES-04 + the resolver tests cover the suppression path headlessly; eyeball rides a later PR's C cell"
- H (live-toggle) — reason="not captured; single-run A/B discipline stands for later PRs"

### PR 1a — accepted 2026-07-17

Captured: A (dark/default, full Now Playing); B (light/default — Now Playing playing + paused,
Library, EQ — the whole Kit re-export path in light); queue-toast cell in B (light, over
selection). Verified vs pre-1a: no visual change; spectrum-at-zero and system-accent segmented
selections confirmed pre-existing.

Deferred cells (TEMP, expiry = sprint end 2026-08-15):
- error-banner cell (A/B/C) — reason="device switch was graceful; needs a real engine error to force"
- EQ-recall-banner cell (A/B/C) — reason="banner is transient; missed the capture window"
- queue-toast cell in A + C — reason="captured in B only"
- CLIP/statusError red cell (A) — reason="peak never crossed the hot threshold during capture; value-identity already proven by the review's Color.red probe"
- pixel-diff — reason="founder eyeballed A/B instead; acceptable given the review's code-level pixel-identity verification of all four migrations"
