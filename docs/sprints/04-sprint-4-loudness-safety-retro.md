# Sprint 4 (US-TONAL-LOUDNESS) Retrospective
## Loudness Safety & Transparent Dynamics — True-Peak Limiter + LUFS Normalization

> **✅ SHIPPED — historical record (Sprint 4, shipped & merged).** This is the as-built/as-planned record, retained for provenance and design detail. The authoritative forward sprint schedule is now [sprint-plan.md](sprint-plan.md).

**Document ID:** SPRINT-4-RETRO-001
**Version:** 1.0
**Date:** 2026-06-16
**Author:** Team retro (audio-dsp-agent · modern-cplus-plus-expert · swiftui-pro), synthesized
**Status:** Engineering milestones M1–M6 complete; founder manual sign-off + merge pending
**Companion docs:** [plan](04-sprint-4-loudness-safety-plan.md) · [spec](04-sprint-4-loudness-safety.md) · [test-plan](04-sprint-4-loudness-safety-test-plan.md)

---

## Executive Summary

Sprint 4 established the **safety floor** of the DSP chain: a state-of-the-art true-peak
look-ahead limiter (−1 dBTP) and an ITU-R BS.1770-5 LUFS meter with transparent, slew-limited
makeup gain, plus loudness metering UI and a hearing-safety EQ clamp. All six engineering
milestones landed on branch `feat/sprint-4-loudness-safety` and are unit-verified. The two
open Done-Done items are human-in-the-loop: founder manual testing and the merge to `main`.

One honest caveat frames the whole sprint: **the RT DSP kernel is not yet in the live playback
graph** (playback is `AVAudioPlayerNode → mainMixerNode`; meters are fed by a Swift tap). The
limiter / makeup / EQ are built and verified but do not yet process live audio — wiring the AU
into the engine is a separate future task. Sprint 4's deliverable is a *correct, verified safety
floor ready to be inserted*, not a floor already in the signal path.

---

## Milestone Outcomes

| Milestone | Outcome | Evidence |
|---|---|---|
| **M1** Limiter hardening | ✅ Monotonic-deque sliding-max peak, linear-domain gain, 144-frame look-ahead, RT-safe | `LimiterModule.h`; harness |
| **M2** LUFS meter + makeup | ✅ BS.1770-5 (two-stage K-weighting, gated integration), off-RT `std::jthread` + lock-free SPSC ring, pre-limiter slew-limited makeup | `LufsMeter.h`, `LoudnessModule.{h,mm}`, `SpscRing.h`; ffmpeg ±0.037 LU; TSan clean |
| **M3** Limiter → SOTA | ✅ 8× polyphase windowed-sinc ISP detector (Kaiser β=8, 24 taps/phase, sidechain-only, hand-rolled Bessel I0), dB-domain dual-stage release + LF hold-extension, margin −0.27 dB | `LimiterModule.h`; ASAN clean; near-Nyquist + anti-pumping tests |
| **M4** Metering UI | ✅ Integrated/short-term LUFS + sample-peak meters via the Swift mixer tap → C++ `LufsMeter` | `UI/Loudness/`, `LoudnessMeterBridge.mm` |
| **M5** Hearing-safety clamp | ✅ Proportional cumulative EQ-gain clamp at the publish chokepoint | `EQSafetyClamp.swift`, `EQViewModel.dispatchAllBands`; harness 13/13 |
| **M6** Validation & docs | ✅ Soak + LUFS oracle re-run green; spec reconciled; this retro | below |

---

## Done-Done Status (per `00-sprint-model.md`)

```
Sprint 4: Loudness Safety & Transparent Dynamics
Story Points: 8–10

Done-Done Checklist:
☐ Code merged to main                      — PENDING (branch ready; PR open)
☑ Unit tests pass                          — C++ harness 17/17; clamp harness 13/13
☑ Integration tests pass (synthetic)       — Limiter_HotNoiseSoak, ceiling, GR<2ms, near-Nyquist
☑ LUFS accuracy ±0.1 LUFS vs ffmpeg ebur128 — 0.037 LU delta
☑ No known regressions in EQ/playback      — app builds clean; EQ dispatch path unchanged in behaviour for in-range shapes
☑ RT-safety: ASAN + TSan clean             — no alloc/lock/throw on render thread
☑ clang-tidy / lint gate green             — pre-commit gate passing on all commits
☐ Manual testing completed by founder      — PENDING (see checklist below)
☑ Documentation updated                    — plan status table, spec reconciliation note, this retro
☑ Team retro completed                     — this document
```

**Soak nuance:** the Done-Done "1-hour soak (0 XRuns)" is satisfied at the DSP level by the
synthetic `Limiter_HotNoiseSoak` harness test (sustained hot noise, no NaN/Inf/alloc). A literal
1-hour *live* soak would currently exercise only `AVAudioPlayerNode → mainMixerNode` playback —
**not** the RT DSP — because the AU is not in the graph yet. Recorded here so the checkbox is not
mistaken for live-DSP soak coverage.

---

## What Went Well

- **Quality-first principle paid off concretely.** The "resources abundant → optimize for sound
  quality" rule drove the M3 choices (8× over 4× oversampling, 24 vs 16 taps, double-precision
  envelope, dual-stage release) — each justified by transparency, not cycles. The same principle
  *rejected* artifact-prone complexity (full-path SRC, band-split, K-weighted sidechain).
- **Verification was real, not aspirational.** ffmpeg `ebur128` as an independent LUFS oracle
  (±0.037 LU), TSan on the SPSC ring (5M items), ASAN on the limiter, and a standalone harness
  that compiles the *real* production code rather than a copy.
- **SOTA survey caught a wrong turn early.** Research showed the planned "B5 K-weighted limiter
  sidechain" would blind a true-peak detector to LF peaks; it was withdrawn before implementation
  and replaced with LF hold-extension.

## What Was Hard / What We'd Change

- **`swift test` is unusable here** (swift-testing macro/framework skew vs the active Xcode
  toolchain). We worked around it with standalone `swiftc`/C++ harnesses, but Swift control-path
  logic (e.g. `EQSafetyClamp`) deserves first-class tests. **Action:** fix the test target (or
  extract a testable `AdaptiveSoundCore` library) — tracked for a future sprint, off critical path.
- **Spec/implementation drift.** The spec's signal-flow diagram (`Loudness → BRIR`) disagreed with
  the built chain (`BRIR → Loudness`) and omitted EQ. Reconciled in M6 with an explicit note rather
  than silently editing the diagram, so the history stays legible.
- **Scope drift via the GUI review.** The GUI-review doc bundled cross-sprint work (seek/progress)
  into a Sprint-4 "M4", which briefly pulled implementation toward Phase 1b Part B. Corrected; the
  lesson — review docs must tag each item with its owning sprint.
- **The AU-not-in-graph reality** means meters show sample-peak + LUFS, not true-peak/GR, and none
  of the DSP affects sound yet. This was the right scope call for Sprint 4 but must be made loud so
  the build is not mistaken for "shipped in the signal path."

---

## Metrics

- C++ DSP harness: **17/17** (limiter #8–#14, loudness #15–#19, identity/bypass).
- EQ clamp harness: **13/13** (both spec clamp tests + edge cases).
- LUFS accuracy: **0.037 LU** vs ffmpeg `ebur128` (tolerance 0.1).
- True-peak margin: **−1 dBTP − 0.27 dB** safety (8×/24-tap polyphase detector).
- Thread safety: TSan clean (SPSC ring, 5M items); ASAN clean (limiter).

---

## Carry-Forward / Deferred

- **Wire the DSP AU into the `AVAudioEngine` graph** — unlocks true-peak + GR meters and makes the
  limiter/makeup/EQ actually process audio. Prerequisite for a meaningful live soak. (Future AU-integration task.)
- **Fix the Swift test target** (or extract `AdaptiveSoundCore`) so control-path logic is testable.
- **Confidence-gated stricter clamp** (spec §4) — deferred to the future Arbiter / NL control plane.
- **Visual polish backlog** — see [08-gui-design-review.md](08-gui-design-review.md).

## Action Items for Sprint 5 (EQ wiring)

1. Sprint 5 assumes the limiter is RT-safe — ✅ satisfied (M1/M3, TSan/ASAN clean).
2. When the AU graph wiring happens, re-validate the chain order `EQ → Clarity → BRIR → Loudness → Limiter`
   end-to-end on a live hot master.
3. Add live true-peak/GR meters once the AU is in the path (the C++ getters already exist).
