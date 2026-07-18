# S10.8 plan — DEVIATIONS.md triage + the Now Playing polish wave

**Input:** `docs/design/now-playing-7a/DEVIATIONS.md` (founder-commissioned external audit of
the 2026-07-19 build vs the 8a card). **This triage reconciles it with the S10.7 decision
record** — the auditor had the screenshot but not the sprint's ledger, so several items are
already shipped, founder-decided, or the D8 feature working as designed. Verified against
code 2026-07-19 (each ✗ below was re-checked in source, not assumed).

## A. Report items that are STALE or BY DESIGN (no action — recorded so nobody "fixes" them)

| Report claim | Reality |
|---|---|
| §2 "bars are LED-segmented, dotted peak marks" | ✗ Bars are SOLID per-bar gradient `RoundedRectangle`s (radius 2); the "dotted marks" ARE the 8a 2pt peak-hold caps @50% opacity 4px above the bar — shipped PR 5 exactly per the 8a spec. |
| §2 "lens is a flat rect with plain border" | ✗ The lens carries the full Regime-B recipe since PR 3/5: `lensFill rgba(16,18,21,.42)`, radius 20, specular rim, hairline (IC variants), bottom bleed, shadow, 4 gridlines. (No blur — deliberate §3.1 policy, see decision 2.) |
| §4 "sliders are native NSSlider" | ✗ `CarvedSlider` shipped PR 5: 5pt carved track + inset shade, teal fill w/ dark-only glow, 14pt knob, full keyboard/VO parity. |
| §5 "glow is the wrong hue (amber/olive)" | ✗ That is **D8 art-sampled glows working** (founder-accepted PR 7; the audited screenshot was taken during a warm-palette album). The missing-art fallback IS brand teal/lime/blue. |
| §7 "scrubber → carved track + knob" | ✗ Shipped PR 6 (shared `CarvedGroove`/`CarvedKnob` with the inspector sliders); founder-accepted. |
| §1/§3 file homes (`RightPanelView`, `NowPlayingInfoView`) | Deleted in PR 5; homes are `NowPlayingTabView` / `InspectorColumn` / `HeroBand`. |

## B. REAL remaining deviations (the work), grouped into PRs

Loop per PR unchanged: build + strict gate → SME review → founder screenshot cells → ledger.
All new colors (#8AF0E0 active title, #FFB347 amber, capsule-tab gradient) enter as
**Palette tokens with light variants through the R4 audit** — never inline.

- **PR-A — zero-risk batch (½ day):** device pill widened so common names don't truncate
  (the PR-6 rate slot squeezed the name — the report's one fresh catch in §1); signed
  `+4.0 dB` master-gain readout; logo glyph → brand waveform mark; headphones paragraph →
  one line + `.help()` tooltip; Bypass/Full-Blend caption style; queue-row `.help(path)`
  tooltips; row format-badge metrics (18pt/radius 9).
- **PR-B — tab selector capsule control (D9 reopen, decision 1):** custom capsule track +
  teal-gradient active capsule + hover states, replacing `.pickerStyle(.segmented)`; keeps
  a11y labels/value + RM gating; matrix H + keyboard cells.
- **PR-C — queue header package:** consolidate QUEUE block + actions + Up Next/Recent +
  filter into ONE header row; filter becomes the compact right-aligned capsule; grips
  hover-only (design has none visible at rest).
- **PR-D — active-row treatment:** teal-16% fill + 1px ring + radius 12 token'd row style;
  active title token (#8AF0E0 → Palette, audited); replace the ▶ glyph with the §3.4 3-bar
  mini equalizer driven by REAL `spectrumBars` low/mid/high (mandated: not a sine loop),
  playing+RM-gated. Also closes the ledger's "row-hover never implemented" §3.4 drop.
- **PR-E — inspector float + meters:** panel hugs content height (stops stretching to the
  window; glow shows beneath), stays top-aligned with the queue header; loudness rows become
  label + 6pt gradient meter + right mono value; **peak row per decision 3**; gradient-fade
  section hairlines.
- **PR-F — hero badge merge:** `ENHANCED · 20%` one badge (pulsing dot kept), `MP3 · 48 kHz`
  format+rate badge (format segment is NEW — source from the file extension), artist·dot
  separation; spoken summary unchanged.
- **PR-G — band glass-look strata (decision 2):** chrome + footer get the Regime-B fill
  strata treatment (fill + specular hairline seams) — NOT real blur (see decision).

## C. Decisions needed (founder), with recommendations

1. **D9 reopen — capsule tab control.** The design doc locked "native segmented; revisit
   only if PR-6 screenshots reject the look." Commissioning this audit effectively reopens
   it. **Recommend: YES, build PR-B** — it is the report's biggest visible gap and the 8a
   card's identity.
2. **Band "glass material (blur + saturation)" (§1/§7/README §2).** Real blur on the bands
   is the §3.1 anti-pattern this sprint deliberately banned (flow-sibling bands have no
   content beneath — "ghost glass"), and the sanctioned real-glass escalation is post-R1
   (design §2). **Recommend: PR-G's token-fill strata now** (same treatment that made the
   lens/panel read as glass), revisit true under-content glass post-R1.
3. **"True peak" rename (§4).** The meter's `peakDb` is SAMPLE-peak with decay (verified:
   `LoudnessMeterBridge.cpp` — "the true-peak limiter is not in this path"). Renaming
   without changing the measurement would be dishonest on an audiophile surface.
   **Recommend: enable true-peak in the libebur128 wrapper** (it supports it) and then
   rename + add the −1 dBTP amber threshold; if that costs more than trivial CPU, keep
   "Peak" and the amber threshold on sample-peak with an honest label.
4. **Scope framing.** **Recommend: this list becomes S10.8 part 1** ("Now Playing polish"),
   with the original 4-tab token sweep as part 2 — R1 gates on both. The break-it round's
   two standing S10.8 design questions (light-mode ambience; whether flat-base tabs need a
   field) remain open for part 2 and are NOT covered by the deviations list (it audited dark
   only).

## D. Sequencing vs the S10.7 close-out

S10.7's two open close-out items happen FIRST:
1. **Instruments/FPS run (founder, 10 min)** — baseline BEFORE PR-B/PR-D add animated
   views (capsule hover states, 88-bar lens + per-row equalizer).
2. **Full A–H pass** — folded into PR-A's founder round (each deviation PR re-exercises the
   matrix anyway; recorded as the close-out adjustment in the ledger).

Then S10.7 closes (retro included), PR #61 un-drafts and merges, and S10.8 opens with PR-A
on a fresh branch.
