# Sprint 4 (US-TONAL-LOUDNESS) Implementation Plan
## Loudness Safety & Transparent Dynamics — True-Peak Limiter + LUFS Normalization

> **✅ SHIPPED — historical record (Sprint 4, shipped & merged).** This is the as-built/as-planned record, retained for provenance and design detail. The authoritative forward sprint schedule is now [sprint-plan.md](sprint-plan.md).

**Document ID:** SPRINT-4-PLAN-001
**Version:** 1.2
**Date:** 2026-06-16
**Author:** Team review (audio-dsp-agent · modern-cplus-plus-expert · swiftui-pro), synthesized
**Status:** M1 (limiter hardening) + M2 (LUFS module) shipped & verified; M3 SOTA-researched and validated below; ready to implement
**Effort:** 8–10 story points
**Prerequisite:** Phase 1b Part B (progress, seek, auto-play, test suite)
**Companion docs:** [04-sprint-4-loudness-safety.md](04-sprint-4-loudness-safety.md) (spec/vision) · [04-sprint-4-loudness-safety-test-plan.md](04-sprint-4-loudness-safety-test-plan.md) (QA)

**Revision history:** v1.0 initial plan → v1.1 M1/M2 implemented → v1.2 M3 state-of-the-art research folded in (online survey of true-peak limiting) and validated against the guiding principle below; the planned **B5 "K-weighted sidechain" is withdrawn** (see §Guiding Principle and §Milestone 3).

---

## Executive Summary

Sprint 4 establishes the **safety floor** of the DSP chain: a true-peak lookahead limiter enforcing a −1 dBTP ceiling, and ITU-R BS.1770-5 LUFS loudness normalization with a transparent makeup gain. A correctly-numbered, expert-reviewed plan matters here because, unlike the stale HANDOFF.md narrative, **the limiter is already implemented and wired** — the real work is hardening it, building the (currently stub) Loudness module, adding the metering UI, and adding hearing-safety clamps. This document is the team-reviewed implementation breakdown; acceptance criteria and validation live in the spec and test-plan companions.

---

## Guiding Architectural Principle (quality-first under resource abundance)

**Assume CPU, RAM, and network are abundant** (modern Apple-Silicon Macs, foreground sole-occupancy, "lean-back listening" — we are the clock). **Optimize every decision for excellent sound quality, not for cycles saved.** Latency in the own-player is essentially free.

This principle is a *quality maximizer, not a "do more everywhere" rule*. It cuts two ways:

- **Where extra compute buys cleaner sound, spend it freely** — higher oversampling, more filter taps, double-precision envelopes, longer look-ahead, dual-stage ballistics. The internet's "transparency-per-CPU" rankings are advisory only; we are not CPU-bound, so we take the higher-quality option whenever it is *audibly* better.
- **Where extra complexity buys *artifacts*, reject it regardless of available CPU** — crossover phase smear, sample-rate-conversion coloration, or a frequency-weighted sidechain that misses real peaks are quality *liabilities*. Abundance never justifies adding them.

Every SOTA finding from the online research is validated against this principle in [§Milestone 3](#milestone-3--limiter-to-state-of-the-art-sota-survey--validation). The litmus test is always: *does this make familiar music sound more transparent on an A/B?* — never *is this cheap enough?*

---

## Verified Current State (read the code, not HANDOFF.md)

| Component | State | Evidence |
|---|---|---|
| **Limiter** | ✅ **M1 hardened & verified** (deque peak, linear-domain gain, +margin, 96-frame lookahead) | `LimiterModule.h`; harness 10/10. *M3 SOTA upgrade pending — see below.* |
| **Loudness (LUFS)** | ✅ **M2 implemented & verified** (BS.1770-5 meter, SPSC ring, off-RT jthread) | `LufsMeter.h`, `LoudnessModule.{h,mm}`, `SpscRing.h`; harness 15/15; ffmpeg oracle ±0.037 LU; TSan clean |
| **Metering UI** | ✅ **M4 implemented** (meters via the Swift mainMixer tap → C++ `LufsMeter`; integrated/short-term LUFS + sample-peak) | `UI/Loudness/`, `LoudnessMeterBridge.mm`, `AudioViewModel.tickSpectrum` |
| **Hearing-safety clamps** | ✅ **M5 implemented & verified** (proportional cumulative-gain clamp in the EQ dispatch chokepoint) | `EQSafetyClamp.swift`, `EQViewModel.dispatchAllBands`; standalone harness 13/13 (`scripts/build-eq-clamp-test.sh`) |
| **`swift test`** | ⚠️ Broken on Xcode-toolchain machines (swift-testing macro/framework skew) | `Package.swift:50–61, 109–120` link CLT `Testing.framework` while the active toolchain is Xcode 6.3.2 |

Signal chain (verified in `DSPKernel.mm`): `EQ → Clarity → BRIR → Loudness → Limiter`.

---

## Key Design Decision — Makeup Gain Placement (cross-expert reconciliation)

The DSP and C++ reviewers disagreed on where the LUFS makeup gain is applied. This is resolved and **locked** for this sprint:

- **audio-dsp-agent** proposed moving makeup gain *after* the limiter to break the makeup↔limiter feedback loop.
- **modern-cplus-plus-expert** assumed makeup *before* the limiter (the current chain).

**Decision: makeup gain stays BEFORE the limiter (current chain order is correct).** Applying *positive* makeup (boosting a quiet track toward −14 LUFS) *after* a true-peak limiter would push the just-constrained peaks back above −1 dBTP, defeating the limiter's entire purpose (DAC headroom / hearing safety). The industry-standard loudness-normalization order — the Spotify/Apple Music model this app cites — is **normalize → then true-peak limit**. The feedback-loop / pumping concern raised by audio-dsp is real but is solved by **time-constant decoupling** (makeup slew ≥ 3–5× slower than the limiter release) + a min-block guard + a ±12 dB clamp, *not* by reordering.

---

## Architecture & Design

### Limiter — M1 hardening (✅ done) + M3 SOTA upgrade (planned)
**M1 (shipped):** replaced the O(frames × lookahead) per-sample rescan with an amortized-O(1) **monotonic-deque sliding-window max**; moved gain to the **linear domain** (deleting per-sample `log10`/`exp`); raised lookahead 48 → 96 frames (2 ms); removed dead `LimiterParams` fields; added a **−0.5 dB interim ISP margin** to cover linear-interp under-read. Harness 10/10.

**M3 (planned, SOTA-validated below):** the linear-interp ISP detector is the remaining quality gap, and the originally-planned "K-weighted sidechain" (B5) is **withdrawn** as incorrect for a safety limiter. The M3 upgrade is: a **polyphase windowed-sinc oversampled true-peak detector** (sidechain-only), **dB-domain gain smoothing + LF hold-extension**, and **dual-stage release** — full design, options, and the quality-first validation are in [§Milestone 3](#milestone-3--limiter-to-state-of-the-art-sota-survey--validation).

### Loudness module (the big build)
**DSP (runs OFF-RT in a measurement thread):** BS.1770-5 — two-stage K-weighting (high-shelf + high-pass; exact 48 kHz biquad coeffs in the test-plan, re-derived via bilinear transform for non-48k), 400 ms blocks / 100 ms hop / 75 % overlap, absolute gate (−70 LUFS) + relative gate (−10 LU), integrated / short-term / momentary LUFS. Makeup gain `= clamp(lufsTarget − measured, −20, +12) dB`, gated behind a **min-4-block guard** before the first update.

**C++ architecture (mirrors the EQModule publish pattern, but no `TargetState` second-producer):**
- RT `process()` does only: push samples into a **lock-free SPSC ring** → read one `std::atomic<float>` makeup gain → apply via `ParameterRamp` + `vDSP_vmul`. No measurement on the RT thread.
- An off-RT **`std::jthread`** (RAII, joined in dtor) drains the ring, runs K-weighting/gating, and publishes makeup gain + measured LUFS via **module-local atomics** — *not* through `TargetState`/`publishTargetState`, preserving the documented single-producer precondition (`DSPKernel.mm:67–69`). The measurement thread may still `acquireSnapshot()` to read `lufsTarget`/`enabled` (multiple consumers are fine).
- **Decoupling:** makeup slew ≤ 0.1 dB / 100 ms (off-RT) + RT ramp τ ≈ 200 ms (≥ 3–5× the 100 ms limiter release) → structurally eliminates limit-cycle pumping while keeping makeup *before* the limiter.
- Under ring starvation the RT producer drops oldest / never blocks (sacrifice measurement accuracy, never RT determinism).

### Metering UI (mirror the existing spectrum pipeline)
- `LoudnessSnapshot` value type + `LoudnessDoubleBuffer` (parallels `SpectrumDoubleBuffer`); `AudioEngineBridge.readLoudnessSnapshot()`; `AudioViewModel.tickLoudness()` on a 10 Hz `Timer`. Single struct assignment = one `@Observable` notification.
- New views under `Sources/AdaptiveSound/UI/Loudness/`: `LoudnessSnapshotView` (single observation point), `LUFSReadoutView` (monospaced `Text`), `TruePeakMeterView` + `GainReductionMeterView` (`Canvas`), optional `GatedLoudnessReadoutView`.
- Placement: a new "Loudness" section in `RightPanelView`, **hidden by default** via `@AppStorage("showLoudnessMeters")` (on the view, not the `@Observable`); `.onChange` starts/stops the timer so polling runs only when visible. VoiceOver labels, Dynamic Type, reduce-motion handled; reuse `SpectrumColorPalette`.

### Hearing-safety clamps (smaller than the spec implies)
No Arbiter/NL control plane exists yet. MVP: in the Swift control path (before publishing `TargetState`), sum the EQ band gains; if > +12 dB, scale all bands by `12/sum` (preserves shape and direction). Pure, unit-testable, no new architecture. Confidence-gating is deferred to the future Arbiter.

---

## Milestone 3 — Limiter to State of the Art: SOTA survey & validation

Online research (audio-dsp-agent + targeted web search) surveyed the state of the art in transparent true-peak limiting. Sources: ITU-R BS.1770-4/-5 Annex 2; libebur128; x42/zita-dpl1; Signalsmith "Designing a Straightforward Limiter" (2022); Daniel Rudrich's look-ahead limiter notes; Giannoulis, Massberg & Reiss, "Digital Dynamic Range Compressor Design" (JAES 2012); FabFilter Pro-L2 / FLUX docs; KVR/Gearspace practitioner consensus.

### SOTA findings (condensed)
1. **ISP detection = polyphase windowed-sinc FIR, sidechain-only.** BS.1770 Annex 2's normative example is a 4×, 12-tap/phase FIR (a "low-cost compromise"). Modern limiters (x42, libebur128) oversample **only the detection sidechain**, not the audio path — the gain envelope from a few-ms look-ahead varies too slowly to alias, so the audio stays at base rate. Linear interpolation (our M1 interim) under-reads the true peak by ~0.5–0.8 dB; a proper polyphase FIR cuts that to <0.05 dB.
2. **Ballistics = feed-forward, dB-domain gain computer, dB-domain release** (Giannoulis et al. 2012) — log-domain release removes the end-of-release "snap" of linear smoothing. **Look-ahead fade-in** (Rudrich): pre-compute a down-ramp that lands exactly on the peak, rather than racing a one-pole — eliminates clicks on short transients.
3. **Bass pumping is fixed by hold-extension, not a weighted sidechain.** Don't release between two closely-spaced LF peaks; the detector must still see full-band.
4. **Dual-stage release** (fast + slow, take the deeper) is the mastering-limiter SOTA for natural behavior on sustained passages.
5. **Reference implementations:** Signalsmith `basics` and Rudrich `SimpleCompressor` are **MIT** (usable); x42/dpl.lv2 and LSP are **GPL** (read-and-reimplement only).

### Options surfaced by the research
- ISP oversampling factor: **4× / 8× / 16× / 32×** (FabFilter reserves ≥8× and 32× offline).
- FIR taps per phase: **12 (BS.1770 min) / 16 / 24–32**; window Kaiser β ≈ 5 (−57 dB) … 8 (−90 dB).
- Oversampling scope: **sidechain-only** vs **full audio path** (with downsample).
- Release: **single one-pole** vs **dual-stage** vs **FIR/Gaussian (BoxStackFilter)** gain smoother.
- Look-ahead: **1.2–2 ms** (real-time SOTA) vs **longer** (own-player latency is free).
- Gain envelope precision: **float** vs **double**.

### Validation against the guiding principle (quality-first under abundance)

The web's recommendations are largely framed as *transparency-per-CPU*; we are **not CPU-bound**, so we re-decide each one by audible quality. Crucially, abundance does **not** mean "max everything" — it means take the higher-*quality* option, and reject complexity that adds *artifacts*.

| Topic | Web / CPU-first stance | **Quality-first decision (ours)** | Why the principle changes (or keeps) it |
|---|---|---|---|
| ISP oversampling factor | "4× sufficient; 8× = diminishing returns" | **8×** | Marginal cost is free; buys extra true-peak headroom + lets us tighten the ceiling margin. 16×/32× add latency/taps for *inaudible* gain → stop at 8×. |
| FIR taps / window | 16 taps/phase, β≈5 (−57 dB) | **24 taps/phase, β≈8 (≈−90 dB)** | Cleaner reconstruction, lower passband ripple; trivially affordable. |
| Oversampling scope | sidechain-only is enough | **sidechain-only (kept)** | NOT a CPU compromise — full-path SRC adds latency + coloration with *zero* quality gain for a smooth-gain limiter. Abundance must not add artifacts. |
| Release ballistics | dual-stage "optional" (safety limiter sees <3 dB GR) | **dual-stage + dB-domain + hold-extension, by default** | Transparency upgrades are free → default them rather than gate on CPU. |
| Look-ahead length | 1.2–2 ms | **~3 ms (configurable up)** | Own-player latency is free; longer look-ahead → gentler, more transparent gain ramps. |
| Gain envelope precision | float | **double envelope** (down-cast at `vDSP_vmul`) | Trivial cost; smoother ramps, no quantization on slow gains. |
| K-weighted / HP sidechain (old **B5**) | don't — misses real LF true peaks | **withdrawn (confirmed)** | Correctness/safety, **principle-independent**. Quality-first does *not* resurrect it: a true-peak ceiling must catch LF peaks too. |
| Band-split limiting | don't — crossover artifacts | **don't (confirmed)** | Crossover phase smear is a quality *liability* on familiar A/B material. Abundance ≠ more complexity. |

**Conclusion.** The abundance principle *upgrades* the cheap-but-cleaner choices (8× OS, 24 taps, dual-stage, double envelope, longer look-ahead) and *upholds* the rejections that protect transparency (no full-path SRC, no weighted sidechain, no band-split). It does not change a single correctness/safety decision.

### Final M3 scope (quality-first, ordered by audible impact)
1. **Polyphase 8×, 24-tap/phase, Kaiser-β8 windowed-sinc true-peak detector (sidechain-only)** → feed the existing deque peak; then tighten the working ceiling margin from −0.5 dB toward −0.1 dB.
2. **dB-domain gain smoothing + Rudrich look-ahead fade-in + LF hold-extension** (replaces the withdrawn B5).
3. **Dual-stage release** (fast ~100 ms + slow ~400–600 ms, take the deeper); look-ahead → ~3 ms.
4. *(debug/regression)* second-pass output true-peak assertion (output ≤ ceiling).

### Verification additions (M3)
- Near-Nyquist ISP test that **fails under linear-interp and passes under polyphase** (output TP ≤ ceiling).
- Hot-master soak: output true-peak ≤ ceiling across many buffers (already #13-style).
- Anti-pumping: 40 Hz tone + transient → no audible gain modulation at the bass rate (assert GR envelope doesn't oscillate at the fundamental).
- Coefficients generated offline (scipy `firwin` Kaiser) and checked into a small generator script for reproducibility.

---

## Implementation Breakdown

### Phase A — Prerequisites (~0.5 sp)
- Use the standalone C++ harness (`Tests/DSPKernelNullTest.cpp` via `scripts/build-null-test.sh`) as the **primary** DSP gate — it compiles and runs today.
- (Parallel, off critical path) fix the `swift test` toolchain skew in `Package.swift` so the Swift test targets compile on Xcode-toolchain machines.

### Phase B — Limiter hardening (~2 sp) — ✅ DONE (M1)
B1 monotonic-deque sliding-window max · B2 linear-domain gain (drop `log10`/`exp`) · B3 −0.5 dB ISP margin · B4 lookahead → 96 frames · B6 remove dead params + use `maxFrames_`. **B5 (K-weighted sidechain) withdrawn** — see §Milestone 3. **B7 (polyphase ISP) promoted into M3** as the SOTA upgrade (8×/24-tap, dB-domain ballistics, dual-stage release).

### Phase C — Loudness module (~3–4 sp) — ✅ DONE (M2)
K-weighting filters · 400 ms/100 ms gated integration · makeup-gain derivation + clamp + min-block guard · off-RT `std::jthread` + SPSC ring + atomic handoffs · RT `ParameterRamp` apply. Verified vs `ffmpeg ebur128` (±0.037 LU); SPSC ring TSan-clean.

### Phase B′ — Limiter SOTA upgrade (~2 sp) — M3 (next)
Polyphase 8×/24-tap windowed-sinc true-peak detector (sidechain-only) · dB-domain smoothing + look-ahead fade-in + LF hold-extension (replaces B5) · dual-stage release · tighten ceiling margin. Full design in §Milestone 3.

### Phase D — Metering UI (~1.5 sp)
Bridge surface + double-buffer + view model tick · `UI/Loudness/` views · `RightPanelView` section + toggle.

### Phase E — Hearing-safety clamps (~1 sp)
Proportional EQ-gain clamp in the Swift control path + unit tests.

### Phase F — Validation & docs (~0.5 sp)
Soak run · spec-doc fixes (note the BRIR-ordering discrepancy in §spec; document the "−1 dBTP" margin) · retro.

---

## Dependencies & Blockers

**Unblocked by:**
- ✅ Phase 1b Part B (progress, seek, auto-play, test suite)
- ✅ Limiter scaffold (exists and wired from Phase 1a)

**Blocks:**
- 🟡 Sprint 5 (EQ wiring assumes the limiter is RT-safe)
- 🟡 Sprint 6 (loudness compensation builds on LUFS measurement)

**Known blocker:** `swift test` does not compile on this machine (swift-testing macro/framework skew). The standalone C++ harness is the workaround and primary gate; fixing the Swift test target is parallelizable and off the critical path.

---

## Risk Mitigation

| Risk | Severity | Mitigation |
|---|---|---|
| Per-sample RT cost (current limiter) overruns budget | High | B1 monotonic deque + B2 linear-domain math; verify with the RT-safety tests |
| Linear-interp ISP under-reads true peak → inter-sample clipping | High | M1 −0.5 dB margin shipped; **M3 polyphase 8×/24-tap detector** (quality-first) then tighten margin to −0.1 dB |
| Makeup↔limiter feedback pumping | Medium | Time-constant decoupling (slew ≥ 3–5× release) + min-block guard + ±12 dB clamp; makeup stays pre-limiter |
| Second producer racing `publishTargetState` | High | Module-local atomics for makeup/LUFS; never route through `TargetState` |
| SPSC ring starvation stalls RT thread | High | Drop-oldest, never block on the RT side |
| Bass pumping from fast TP attack | Medium | **LF hold-extension** (M3) — *not* a weighted sidechain (B5 withdrawn: would miss real LF true peaks) |
| LUFS inaccuracy vs reference | Medium | Validate ±0.1 LUFS vs `ffmpeg ebur128` (see test-plan) |

---

## Definition of Done (per `00-sprint-model.md`)

- [ ] Code merged to main
- [ ] Unit tests pass — limiter (#9–#14), loudness (#15–#20), clamps; null-test bit-exact bypass
- [ ] Integration tests pass — 1-hour soak (0 XRuns, stable metering), peak-protection on synthetic hot master
- [ ] LUFS accuracy ±0.1 LUFS verified vs `ffmpeg ebur128`
- [ ] No known regressions in EQ/playback
- [ ] RT-safety: ASAN + ThreadSanitizer clean; no allocation/lock on the render thread
- [ ] clang-tidy / lint gate green
- [ ] Manual testing completed by founder (see test-plan checklist)
- [ ] Documentation updated (spec doc + this plan; architecture.md §16 if design changes)
- [ ] Team retro completed (`04-sprint-4-loudness-safety-retro.md`)

---

## Timeline (effort-driven, not calendar-driven)

- **Milestone 1:** ✅ Phase A + B — limiter hardened & RT-safe; harness 10/10.
- **Milestone 2:** ✅ Phase C — Loudness DSP + off-RT thread; harness 15/15; ffmpeg oracle ±0.037 LU; TSan clean.
- **Milestone 3:** ✅ Phase B′ — limiter SOTA upgrade (polyphase 8× ISP detector, dB-domain + hold-extension ballistics, dual-stage release); anti-pumping + near-Nyquist ISP tests. *(B5 withdrawn — quality-first validation above.)*
- **Milestone 4:** ✅ Phase D — metering UI (via the Swift mixer tap; sample-peak + LUFS).
- **Milestone 5:** ✅ Phase E — hearing-safety clamp (`EQSafetyClamp`; harness 13/13).
- **Milestone 6:** ✅ Phase F — soak (harness 17/17) + LUFS oracle re-run (±0.037 LU) + spec reconciliation + [retro](04-sprint-4-loudness-safety-retro.md).

---

**Status:** Engineering complete (M1–M6) on `feat/sprint-4-loudness-safety`; founder manual sign-off + merge to `main` pending.
**Next:** Begin Milestone 1 (limiter hardening) after Phase 1b Part B ships
