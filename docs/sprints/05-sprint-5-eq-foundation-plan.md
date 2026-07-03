# Sprint 5 (US-TONAL-EQ) Implementation Plan
## Minimum-Phase EQ Wiring & Spectral Correction — DSP AU into the Live Graph

> **✅ SHIPPED — historical record (Sprint 5, shipped & merged).** This is the as-built/as-planned record, retained for provenance and design detail. The authoritative forward sprint schedule is now [sprint-plan.md](sprint-plan.md).

**Document ID:** SPRINT-5-PLAN-001
**Version:** 1.0
**Date:** 2026-06-16
**Author:** Synthesized from the AU-graph de-risk spike + the Sprint 5 spec; expert-review gates noted per phase
**Status:** Core risk retired by spike; scope locked to M1–M3 (core); ready to implement
**Effort:** 7–9 story points (M1–M3 core + M4 validation). AutoEq profiles + master-gain relocation split to **Sprint 5b**.
**Prerequisite:** Sprint 4 (limiter + LUFS built & verified) — PR #14
**Companion docs:** [spec](05-sprint-5-eq-foundation.md) · [AU-graph spike notes](05-sprint-5-au-graph-spike-notes.md)

---

## Executive Summary

Sprint 5 makes the DSP **audible**. The Sprint 4 limiter, loudness makeup, and the 31-band EQ are
all built and unit-verified but sit in an `AUAudioUnit` (`AdaptiveSoundAU`) that is **not in the
playback graph** — playback is bare `AVAudioPlayerNode → mainMixerNode`. The headline work is to
insert that AU into the live `AVAudioEngine` graph and drive the EQ from the UI through the
control plane, so **moving a slider changes what you hear**. Wiring the AU lights up the Sprint-4
limiter and loudness makeup at the same time (all five modules share `DSPKernel::process()`).

A throwaway de-risk spike (see the spike-notes companion) already **proved this works
end-to-end** — register → `AVAudioUnit.instantiate` → attach → connect `player → AU → mixer` →
offline-render a clean passthrough sine, all blocks `.success`. The two concrete gaps it found
(`internalRenderBlock` nil at attach; no input/output bus arrays) are standard v3-AU boilerplate
and are M1's first tasks. So the riskiest unknown is retired; what remains is careful RT-safe
implementation plus the EQ control-plane bridge.

This plan keeps the §Guiding Principle from Sprint 4 (quality-first; resources abundant): we
prefer minimum-phase biquad accuracy and zipper-free ramps over cycle-saving, and reject
artifact-prone shortcuts.

---

## Current State (verified)

| Component | State | Evidence |
|---|---|---|
| **DSP AU (`AdaptiveSoundAU`)** | Built, RT-hardened render block; **not attached** to the engine; created via `alloc/init` only (never registered/instantiated as a node) | `AudioEngine/AUAudioUnit.mm` |
| **AU-graph integration** | **Proven feasible** by spike; needs register + bus arrays + render-block-at-init | [spike notes](05-sprint-5-au-graph-spike-notes.md) |
| **EQ DSP** | `EQModule` + `EQModuleCoefficients` (minimum-phase biquad design) implemented & unit-tested (Phase 1a) | `EQ/EQModule.*`, `AudioDSPTests` |
| **EQ control path** | `EQViewModel` clamps + dispatches 31 band gains to `AudioViewModel.setParameter` — which currently has **no path to the kernel** (`setAUParameter` is a stub) | `EQViewModel.swift`, `AUAudioUnit.mm:215` |
| **Kernel control plane** | Driven by whole-`TargetState` publication (`publishTargetState`); no Swift-side `TargetState` builder exists | `AUAudioUnit.mm:233`, `TargetState.h` |
| **Spectrum** | Before-DSP only: one tap on `mainMixerNode` (also feeds LUFS meters) | `AudioEngineBridge.installSpectrumTap` |
| **Master gain** | On the mixer (pre-DSP); spec wants it post-limiter | `AudioEngineBridge.swift` |

---

## Scope (locked)

**Sprint 5 = M1–M3 (core) + M4 (validation/retro): "users hear EQ."** This is the true sprint goal
and the dependency for Sprint 6 / release: insert the AU into the live graph, drive EQ from the UI
through the control plane, and add the before/after spectrum.

**Deferred to Sprint 5b:** AutoEq device profiles and master-gain relocation (see §Sprint 5b
below). Founder decision (2026-06-16): ship the headline outcome first; these are separable and do
not block it.

---

## Milestones

### M1 — DSP AU into the live graph *(core; ~3 sp)*
Make the kernel process live audio. Implement the spike's fixes **properly** (RT-safe, reviewed):

1. **Registration / instantiation**: add `registerAdaptiveAudioUnitSubclass()` +
   `adaptiveAudioUnitComponentDescription()` (C-ABI) and instantiate via
   `AVAudioUnit.instantiate(with:options:)` in Swift.
2. **`internalRenderBlock` lifetime**: build the kernel + render block at `-init` (not in
   `allocateRenderResources`) so the block is non-nil at attach. Preserve the existing RT-safety
   invariant: the block captures the kernel `shared_ptr` by value, never touches `self`/weak refs,
   no alloc/lock/throw on the render thread. `allocateRenderResources` only re-`initialize`s the
   kernel for the negotiated format; reconsider `deallocateRenderResources` (don't free a kernel a
   live block still co-owns).
3. **Bus arrays**: declare one stereo input + one stereo output `AUAudioUnitBus`/`Bus­Array`;
   override `-inputBusses`/`-outputBusses`.
4. **Engine wiring**: in `AudioEngineBridge`, change `player → mainMixer` to
   `player → AdaptiveSoundAU → mainMixer`. Keep the existing mixer tap (meters) working.
5. **Format / sample-rate negotiation**: 48 kHz stereo float matched directly in the spike;
   handle device sample-rate changes via `allocateRenderResources` re-init.
6. **Lifecycle**: create on `initialize()`, destroy on `shutdown()`; no leaks.

**Verify:** default-state **bit-exact / ≤ −120 dB passthrough** (intensity-zero bypass holds end-to-end);
existing LUFS/spectrum meters unaffected; ASAN + TSan clean; **no xruns** in a manual-render and a
live soak. *(Expert gate: modern-cplus-plus-expert reviews render-block lifetime + RT-safety.)*

### M2 — EQ control plane: Realizer + `TargetState` bridge *(core; ~3 sp)*
Make slider moves audible.

1. **Realizer (off-RT)**: from the 31 band gains (post `EQSafetyClamp`), compute minimum-phase
   biquad coefficients via the existing `EQModuleCoefficients`, assemble a `TargetState`.
2. **`TargetState` bridge**: add a C-ABI to build/populate a `TargetState` from Swift (the EQ
   sub-state at minimum) and publish it via `publishTargetState`. Replace the no-op
   `setParameter`→`setAUParameter` path: `EQViewModel.dispatchAllBands` → Realizer → publish.
3. **Parameter ramping**: ensure the kernel's existing `ParameterRamp` smooths coefficient changes
   (no zipper noise) on publish.

**Verify (per spec):** single-band boost FR accuracy **±0.5 dB**; band isolation; gain linearity
±20 dB; **THD+N ≤ −90 dB**; zipper-free ramp; slider→audio latency **< 50 ms**. Reuse/extend
`AudioDSPTests/EQTests`. *(Expert gate: audio-dsp-agent reviews the Realizer + minimum-phase validation.)*

### M3 — After-DSP spectrum tap (before/after) *(core; ~1.5 sp)*
Install a second spectrum tap on the **AU output bus** (processed audio); display before/after
(2×2 L/R) reusing `SpectrumDoubleBuffer` + `SpectrumColorPalette`. *(Expert gate: swiftui-pro.)*

### M4 — Validation, docs & retro *(core; ~1 sp)*
5-minute multi-track soak (0 xruns); optional MUSHRA listening panel; spec/plan status; retro
(`05-sprint-5-eq-foundation-retro.md`).

---

## Deferred to Sprint 5b

These are scoped, ready, and intentionally split out so Sprint 5 ships the headline outcome first:

- **AutoEq device profiles (~2 sp):** 5 Crinacle-derived JSON profiles; fuzzy-match the connected
  device name; profile as baseline, user gains add on top; feeds the M2 Realizer.
- **Master-gain relocation post-DSP (~1 sp):** move master/volume gain to after the limiter so
  volume is independent of the EQ/spectrum display.

---

## Dependencies & Blockers

**Unblocked by:** ✅ Sprint 4 DSP (limiter/loudness verified); ✅ `EQModuleCoefficients` (Phase 1a);
✅ AU-graph feasibility (spike).

**Blocks:** 🟡 Sprint 6 (clarity builds on live EQ); 🟡 Phase 1c release (EQ is the headline).

**Known blocker (unchanged):** `swift test` is broken here (swift-testing skew). DSP gate stays the
standalone C++/`swiftc` harnesses; AU-graph integration is verified via the offline-render harness
pattern the spike established.

---

## Risk Mitigation

| Risk | Severity | Mitigation |
|---|---|---|
| AU-graph integration unknown | ~~High~~ **Retired** | De-risk spike rendered the AU in-graph end-to-end |
| Render-block lifetime / RT-safety regression when moving block to `-init` | High | Keep capture-by-value invariant; modern-cpp review; TSan/ASAN; passthrough null-test |
| EQ inaudible because control path never reaches the kernel | High | M2 Realizer + `TargetState` bridge replaces the stub `setAUParameter` path |
| Zipper noise on slider moves | Medium | Kernel `ParameterRamp`; zipper test (spectrogram) |
| Device sample-rate change mid-session | Medium | `allocateRenderResources` re-init on format change |
| Scope overrun (AutoEq + master-gain) | Medium | M4–M5 are separable; clean cut after M3 → Sprint 5b |

---

## Definition of Done (per `00-sprint-model.md`)

- [ ] Code merged to main
- [ ] EQ audible: slider move → audio change < 50 ms; FR ±0.5 dB; THD+N ≤ −90 dB; no zipper
- [ ] Passthrough null-test: 0 dB EQ + intensity-zero = bit-exact (≤ −120 dB)
- [ ] AU in graph; limiter + loudness now process live audio; meters still correct
- [ ] After-DSP spectrum tap functional (visual change matches audio)
- [ ] No regressions in playback/meters; 5-min soak 0 xruns
- [ ] ASAN + TSan clean; lint gate green
- [ ] Founder manual sign-off; docs updated; retro (`05-sprint-5-eq-foundation-retro.md`)

---

## Timeline (effort-driven)

- **M1:** AU into the live graph (register/instantiate/attach/connect; render-block lifetime; bus arrays).
- **M2:** EQ Realizer + `TargetState` bridge → slider moves audible.
- **M3:** After-DSP before/after spectrum.
- **M4:** soak + listening panel + retro.
- **Sprint 5b (later):** AutoEq device profiles; master-gain relocation.

---

**Status:** Scope locked to M1–M3 + M4. Ready to implement M1 (spike-proven) once Sprint 4 (PR #14)
merges to main — the Sprint 5 branch builds on it.
