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

Expected traversal: hero (title group) → lens frame ("Spectrum analyzer", carries the
"Open Monitoring" accessibility action + keyboard activation) → queue (first focus via
`.defaultFocus`; ↑/↓/Return work) → inspector: gain slider → intensity slider → meters →
crossfeed toggle — each slider focusable with VISIBLE focus ring, ←/→ adjusts by one step,
VoiceOver announces label + value and supports adjustable. Footer transport reachable after
the tab content. A keyboard user who can reach but not OPERATE a control = PR failure.

## Ledger

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
