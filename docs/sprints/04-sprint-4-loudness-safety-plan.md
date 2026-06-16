# Sprint 4 (US-TONAL-LOUDNESS) Implementation Plan
## Loudness Safety & Transparent Dynamics — True-Peak Limiter + LUFS Normalization

**Document ID:** SPRINT-4-PLAN-001
**Version:** 1.0
**Date:** 2026-06-16
**Author:** Team review (audio-dsp-agent · modern-cplus-plus-expert · swiftui-pro), synthesized
**Status:** Ready for Implementation
**Effort:** 8–10 story points
**Prerequisite:** Phase 1b Part B (progress, seek, auto-play, test suite)
**Companion docs:** [04-sprint-4-loudness-safety.md](04-sprint-4-loudness-safety.md) (spec/vision) · [04-sprint-4-loudness-safety-test-plan.md](04-sprint-4-loudness-safety-test-plan.md) (QA)

---

## Executive Summary

Sprint 4 establishes the **safety floor** of the DSP chain: a true-peak lookahead limiter enforcing a −1 dBTP ceiling, and ITU-R BS.1770-5 LUFS loudness normalization with a transparent makeup gain. A correctly-numbered, expert-reviewed plan matters here because, unlike the stale HANDOFF.md narrative, **the limiter is already implemented and wired** — the real work is hardening it, building the (currently stub) Loudness module, adding the metering UI, and adding hearing-safety clamps. This document is the team-reviewed implementation breakdown; acceptance criteria and validation live in the spec and test-plan companions.

---

## Verified Current State (read the code, not HANDOFF.md)

| Component | State | Evidence |
|---|---|---|
| **Limiter** | ✅ Fully implemented; wired into the chain | `Sources/AudioDSP/Limiting/LimiterModule.h` (427 lines), called at `DSPKernel.mm:101`; `TargetState::LimiterParams` present; null tests #8/#9 in `Tests/DSPKernelNullTest.cpp` |
| **Loudness (LUFS)** | ❌ Stub (empty no-op `initialize`/`process`) — largest gap | `Sources/AudioDSP/Loudness/LoudnessModule.h` |
| **Metering UI** | ❌ Not started | — |
| **Hearing-safety clamps** | ❌ Not started (no Arbiter/control plane exists yet) | — |
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

### Limiter (hardening — DSP + RT-safety)
The implementation is correct in structure but has an RT-cost problem and uses linear-interp ISP detection:
- **RT cost:** `scanLookahead()` re-scans the full 48-sample window every sample → O(frames × lookahead) ≈ 62 M scalar ops/s at 512f/48 kHz, plus a per-sample `std::log10` (line 253) and `std::exp` (line 266). Replace with an amortized-O(1) **monotonic-deque sliding-window max** and move gain math to the **linear domain** (`g = ceil/peak`, smoothed like EQ's `ParameterRamp`) — deleting both transcendentals from the loop.
- **True-peak accuracy:** 4× linear interpolation under-reads the true peak by ~0.5–0.8 dB vs polyphase (BS.1770-5 Annex). For MVP, add **0.5 dB margin** (internal working ceiling ≈ 0.841 ≈ −1.5 dBTP, displayed as "−1 dBTP"); a proper FIR polyphase upsampler is a deferred follow-up (Workstream B7).
- **Ballistics:** raise lookahead 48 → 96 frames (2 ms) so the 0.5 ms attack (5τ ≈ 2.5 ms) converges before the peak arrives; **K-weight the sidechain** (reuse the LUFS filter) to prevent bass pumping.
- **Dead state:** remove unused `LimiterParams::attackCoeff`/`releaseCoeff`/`lookaheadFrames` (`TargetState.h:58–60`); use the stored `maxFrames_` for the block clamp (not hardcoded `kDefaultMaxFrames`) and fail loudly on oversize host blocks. Confirm `TargetState` `static_assert`s still hold.

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

## Implementation Breakdown

### Phase A — Prerequisites (~0.5 sp)
- Use the standalone C++ harness (`Tests/DSPKernelNullTest.cpp` via `scripts/build-null-test.sh`) as the **primary** DSP gate — it compiles and runs today.
- (Parallel, off critical path) fix the `swift test` toolchain skew in `Package.swift` so the Swift test targets compile on Xcode-toolchain machines.

### Phase B — Limiter hardening (~2 sp)
B1 monotonic-deque sliding-window max · B2 linear-domain gain (drop `log10`/`exp`) · B3 +0.5 dB ISP margin · B4 lookahead → 96 frames · B5 K-weighted sidechain · B6 remove dead params + use `maxFrames_`. (B7 FIR polyphase ISP = deferred follow-up.)

### Phase C — Loudness module (~3–4 sp)
K-weighting filters · 400 ms/100 ms gated integration · makeup-gain derivation + clamp + min-block guard · off-RT `std::jthread` + SPSC ring + atomic handoffs · RT `ParameterRamp` apply.

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
| Linear-interp ISP under-reads true peak → inter-sample clipping | High | B3 +0.5 dB margin now; B7 FIR polyphase before GA |
| Makeup↔limiter feedback pumping | Medium | Time-constant decoupling (slew ≥ 3–5× release) + min-block guard + ±12 dB clamp; makeup stays pre-limiter |
| Second producer racing `publishTargetState` | High | Module-local atomics for makeup/LUFS; never route through `TargetState` |
| SPSC ring starvation stalls RT thread | High | Drop-oldest, never block on the RT side |
| Bass pumping from fast TP attack | Medium | B5 K-weighted sidechain (reuse LUFS filter) |
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

- **Milestone 1:** Phase A + B — limiter hardened & RT-safe; harness tests #9–#14 green.
- **Milestone 2:** Phase C — Loudness DSP + off-RT thread; tests #15–#20 vs `ffmpeg ebur128`.
- **Milestone 3:** B5 sidechain K-weighting + makeup/limiter decoupling validated (no pumping).
- **Milestone 4:** Phase D — metering UI.
- **Milestone 5:** Phase E — hearing-safety clamps.
- **Milestone 6:** Phase F — soak, spec-doc fixes, retro.

---

**Status:** Ready for Implementation
**Next:** Begin Milestone 1 (limiter hardening) after Phase 1b Part B ships
