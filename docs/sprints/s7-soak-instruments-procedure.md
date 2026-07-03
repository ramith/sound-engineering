# S7 US-QA-06 — Soak / XRun Verification (Instruments procedure)

**Document ID:** S7-QA06-SOAK-001
**Date:** 2026-06-19
**Status:** Procedure for the founder's on-hardware run. The **allocation** half is automated (see below); the **XRun** half is inherently a real-device Instruments session.

---

## What QA-06 asserts

Over an extended (≈1 hour) continuous playback soak:
1. **Zero audio-thread heap allocations** on the processing path.
2. **Zero XRuns / audio overloads** (no dropouts, no missed render deadlines).
3. **Bounded per-buffer work** (no drift / leak over time).

## Split: automated vs on-hardware

| Part | How | Where |
|---|---|---|
| **(1) Zero RT allocations + (3) bounded work** | **Automated** — `Tests/SoakRtAllocTests.inc` runs `DSPKernel::process` (full chain + intensity-blend path) and the `GaplessSource` RT pull (incl. seam straddle) for the full 1 hr-equivalent (337,500 buffers @ 512/48 kHz) under a thread-local `operator new`/`delete` guard that **fails on any heap allocation on the processing thread**, and checks per-buffer timing stays bounded. Runs on every `bash scripts/build-null-test.sh`. | C++ null-test gate (`Soak_DSPKernel_ZeroRtAlloc_FullChain`, `_Blend`, `Soak_GaplessSource_ZeroRtAlloc_Pull`) |
| **(2) Zero XRuns** | **On-hardware Instruments run** (this procedure) — the harness has no real audio device, so XRuns can only be observed driving CoreAudio on actual hardware. | Founder |

The automated guard catches RT-allocation **regressions** in CI; the XRun check below validates real-device behaviour and is the by-hand counterpart to the by-ear checks.

---

## Instruments procedure (XRun / overload soak)

**Setup**
1. `make build` (release-ish debug bundle) → launch the app (`make run`), or attach to the running app.
2. Load a long playlist (or a folder) — at least ~1 hour of material; enable **repeat** so it loops unattended. Use a **same-rate** set so gapless seams exercise the Pure `GaplessSource` path (and a mixed-rate set in a second pass to exercise the Enhanced resampler seams).
3. Pick the output device under test (built-in, then a USB DAC if available, then Bluetooth). Run the soak once per device class you care about.

**Instruments**
1. Open **Instruments → Audio System Trace** (or *Time Profiler* + the *Audio* track). This surfaces **overloads / XRuns** (the CoreAudio render deadline misses) directly on the timeline.
2. Add the **Allocations** instrument as a cross-check; filter to the audio render thread — there should be **no allocation events on that thread** during steady-state playback (this mirrors what the automated guard proves offline).
3. Optionally add **os_signpost** / the **Points of Interest** track if the render path emits signposts.

**Run**
- Start recording, let it play for **≥1 hour** (longer is better; overnight is ideal for catching rare periodic events).
- Mid-run, exercise the real-world stressors the engine must survive: a few **device switches** (the Tier-2 concurrency fix), **seek**, **volume** changes, **pause/resume**, and a couple of **track-skip** operations.

**Pass criteria**
- ✅ **Zero overloads / XRuns** on the Audio System Trace over the full soak (including across gapless seams and device switches).
- ✅ **No allocations on the audio render thread** during steady-state (the Allocations cross-check; the automated guard is the regression gate).
- ✅ No audible dropouts/glitches by ear; CPU on the audio thread stays flat (no upward drift).

**If a finding appears**
- Note the timestamp + what was happening (seam? device switch? steady-state?), capture the trace, and file it. A steady-state XRun or an audio-thread allocation is a real bug — do not dismiss it.

---

**Maintained by:** AdaptiveSound team · **Automated half:** `Tests/SoakRtAllocTests.inc` (null-test gate) · **Feeds:** [sprint-plan.md](sprint-plan.md) (S7 US-QA-06).
