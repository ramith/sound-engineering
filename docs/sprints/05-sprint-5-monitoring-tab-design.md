# Sprint 5 M3 (re-scoped) — Monitoring Tab Design

**Document ID:** SPRINT-5-M3-MONITORING-001
**Date:** 2026-06-16
**Author:** Synthesized from a 5-discipline panel review (PM · BA · UI/UX · SwiftUI · audio-DSP)
**Status:** Decisions locked; ready to implement
**Supersedes:** the original M3 ("after-DSP before/after spectrum inside Now Playing")

---

## Why this exists

The founder requested a **dedicated Monitoring tab** instead of cramming before/after into Now
Playing: per-channel before/after needs real estate, Now Playing stays uncluttered, and the tab
becomes the home for future visual monitors. Double-clicking the Now Playing spectrum jumps to it.
This re-scopes M3 from a Now-Playing overlay to a Monitoring tab v1.

## Panel verdict (consensus)

Feasible and clean. Key agreements:
- Navigation hooks are clean: add a `.monitoring` case to `TabSelection`; `TabContentView` +
  the toolbar segmented control pick it up automatically.
- **Two taps**: BEFORE = tap the player node (pre-DSP); AFTER = the existing `mainMixer` tap
  (post-DSP). One tap per bus, different nodes → no conflict. (The ~3 ms limiter look-ahead skew
  is imperceptible at the display rate.)
- The current `SpectrumAnalyzer` sums to mono → need a **per-channel** path. 4 extra FFTs/cycle is
  trivial (~100 µs/window; abundant-CPU principle).
- **Honest comparison**: before/after must use identical FFT/window/scaling/ballistics, with a
  null-test asserting ~0 dB delta when the AU is bypassed.
- Render with `Canvas` + `TimelineView` (not 4×88 animated rects); **poll only when the tab is
  visible**.
- `selectedTab` moves from `ContentView` `@State` into `AudioViewModel` (`@Observable`) so a
  double-click deep in Now Playing can switch tabs without binding-plumbing.

## Locked decisions (founder, 2026-06-16)

1. **v1 scope = before/after spectrum only** (per-channel L/R). LUFS history, per-channel
   peak/RMS, GR, true-peak, goniometer, spectrogram, EQ phase overlay are **deferred** (backlog
   below). Built so they're cheap to add.
2. **Layout = group by channel.** One full-width row **per channel**; within a row,
   **Before (left) | After (right)**, split by a hairline. Future monitors add rows below.

> **N-channel (founder mandate, 2026-06-16).** Monitoring is **not hardcoded to stereo**: the
> engine builds one analyzer per channel for each tap point, sized from the stream format, so the
> tab renders one row per channel — 1 row for mono, 2 for stereo (today), up to 8 for 7.1. The
> separate, larger **multichannel *processing/rendering* epic** (make the C++ DSP kernel + AU bus
> N-channel, no naive downmix, spatial-render at the device boundary) is designed in its own doc:
> [05-sprint-5b-multichannel-pipeline-plan.md](05-sprint-5b-multichannel-pipeline-plan.md). The
> monitoring plumbing here is already N-channel-ready and will light up extra rows automatically
> once that epic lands.

```
┌── L ───────────────────────────────────────────┐
│ BEFORE (teal)        ╎        AFTER (blue)       │
│ ▓▓▓░▓▓░░░░░          ╎        ▓▓▓▓▓▓░░░░░         │
└─────────────────────────────────────────────────┘
┌── R ───────────────────────────────────────────┐
│ BEFORE (teal)        ╎        AFTER (blue)       │
│ ▓▓░░▓▓▓░░░░          ╎        ▓▓▓▓▓░░░░░░         │
└─────────────────────────────────────────────────┘
        ··· future monitors add rows below ···
```

## Architecture (v1)

**Navigation**
- `TabSelection.monitoring` (icon `waveform.and.magnifyingglass`, between EQ and Settings).
- `selectedTab` lives on `AudioViewModel`; `ContentView` binds via `@Bindable`. `ToolbarView`
  keeps its `@Binding`.
- Now Playing spectrum (`SpectrumAnalyzerView`) gets `.onTapGesture(count: 2)` → set
  `selectedTab = .monitoring`, plus a hover "expand" cue + `.help(…)` tooltip for discoverability.
  Now Playing is otherwise unchanged.

**Signal / DSP**
- `SpectrumAnalyzer` refactor: extract the FFT pipeline (steps 2–8) so it can be fed either by the
  mono-sum (existing, Now Playing) or by a **single chosen channel** (new). Add
  `processTapBuffer(…, channel: Int)`.
- New BEFORE tap on the player node. Four monitoring analyzers — beforeL/beforeR (player tap),
  afterL/afterR (existing mixer tap) — each fed one channel. The existing mono analyzer (Now
  Playing) and LUFS meter are untouched.
- Engine exposes the four band arrays (lock-free double-buffer reads) via the
  `AudioPlaybackEngine` protocol.

**UI**
- `MonitoringViewModel` (`@Observable`): owns the 4 band arrays, polls the engine on a timer that
  **starts/stops with tab visibility** (`.task` / `.onDisappear`).
- `MonitorSpectrumView` (`Canvas` + `TimelineView`): one reusable before/after-aware spectrum.
- `MonitoringTabView`: two channel rows (L, R), Before | After per row, hairline divider, channel
  + stage labels; reuses `DesignSystem` + `SpectrumColorPalette` (teal=before, blue=after, both
  full opacity). Dimmed when not playing.

**Extensibility (designed-for, not pre-built)**
v1 ships spectrum only on a clean `MonitoringViewModel` + reusable panel component, so adding a
monitor later = add data + a view + a row. The full `LiveMonitor` protocol/registry is adopted
when the 2nd monitor type lands (avoid speculative machinery now).

## Deferred monitor backlog (growth order, from the DSP review)

| Monitor | Needs | Tier |
|---|---|---|
| LUFS momentary history graph | Swift ring only (data already polled) | next, no C++ |
| Per-channel peak + RMS | vDSP in the existing tap | next, no C++ |
| Limiter gain-reduction meter | new `LimiterModule` getter + C-ABI | needs C++ getter |
| True-peak meter | new `LimiterModule` getter | needs C++ getter |
| Goniometer / correlation | L/R sample ring | Swift ring |
| Spectrogram | FFT-history ring | Swift ring |
| EQ phase / group-delay overlay | analytical from biquad coeffs | analytical |

## Acceptance (v1)

- Monitoring tab appears; reachable via toolbar AND via double-click on the Now Playing spectrum;
  return via the toolbar.
- Four live per-channel spectra (before L/R, after L/R), grouped by channel, animating with audio.
- BEFORE vs AFTER visibly diverges when EQ is active; ~identical when EQ flat (honest comparison).
- No playback regressions; dimmed/idle when stopped; no xruns; tap callbacks RT-safe.
- Polling stops when the tab isn't visible. Build-verified (UI is visually verified by the founder).

## Risks

- 4 extra FFTs always-on during playback → accepted (abundant CPU); polling gated to the tab.
- Segmented control with a 4th tab may get tight at min width → icon-only fallback if needed.
- `Canvas`/`TimelineView` redraw cadence vs `@Observable` updates → drive redraw from TimelineView,
  read band data inside the closure.
