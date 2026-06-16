# Sprint 5 Pre-Plan — AU-Graph Integration De-Risk Spike (Findings)

**Date:** 2026-06-16
**Status:** Spike complete — AU-graph integration **proven feasible**; throwaway code reverted; findings folded into the Sprint 5 plan.
**Why:** Sprint 4 left the DSP kernel built but **not in the live playback graph** (see [[reference-dsp-au-not-in-playback-graph]]). Sprint 5's headline deliverable is wiring the AU in so EQ (and the Sprint-4 limiter/loudness) actually process audio. Before committing a plan, we ran a throwaway spike to retire the single biggest unknown: *can the custom v3 `AdaptiveSoundAU` be registered, instantiated as an `AVAudioUnit`, attached to `AVAudioEngine`, and rendered in-graph?*

---

## Result: YES — full end-to-end render works

Headless proof via `AVAudioEngine` **offline manual rendering** (`player → AU → mainMixer`, the AU being the only path to the mixer, so a clean output sine proves the AU's render block ran):

```
step 1 ok: registered AU (type=1635083896 'aufx' subType=1633973092 'adsd')
step 2 ok: instantiated AVAudioUnit; auAudioUnit class = AdaptiveSoundAU
step 3 ok: attached + connected player -> AU -> mainMixer
step 4 ok: offline-rendered 48000 frames over 94 blocks, all .success
input peak = 0.25, output peak = 0.25, output RMS = 0.17554  (ideal sine RMS = 0.17678)
ALL SPIKE CHECKS PASSED
```

A 1 kHz, −12 dBFS sine passed through the custom AU intact (peak preserved, finite, non-silent, near-ideal RMS), confirming a stable, correct render path at the default DSP state.

---

## The two concrete gaps the spike surfaced (and fixed spike-grade)

Both are standard v3-AU requirements the current `AdaptiveSoundAU` does not satisfy. They are the **first implementation tasks of Sprint 5 M1**.

### Gap 1 — `internalRenderBlock` is nil at attach
`AVAudioEngine.attach(auNode)` asserts `required condition is false: RenderBlock()`. The AU only builds `_renderBlock` inside `allocateRenderResourcesAndReturnError:`, but the engine requires a non-nil render block **at attach time** (before resources are allocated).

**Fix:** create the kernel and the render block at `-init` (capturing the kernel `shared_ptr` by value, as today), and have `allocateRenderResources` only (re)`initialize` the kernel for the negotiated format. Keep the RT-safety property that the block never touches `self`/weak refs.

### Gap 2 — no input/output bus arrays → `engine.connect` fails
`engine.connect(player, to: auNode)` asserts `inDestImpl->NumberInputs() > 0 || …CanResizeNumberOfInputs()`. The AU declares no busses, so nothing can connect to it.

**Fix:** declare one stereo input + one stereo output `AUAudioUnitBus` (each `initWithFormat:`), wrap in `AUAudioUnitBusArray`s, and override `-inputBusses` / `-outputBusses`.

### Plus: a clean registration entry point was needed
`createAdaptiveAudioUnit()` only `alloc/init`s the subclass; it never registers the component or produces an `AVAudioUnit` node. The spike added `registerAdaptiveAudioUnitSubclass()` + `adaptiveAudioUnitComponentDescription()` (via `[AUAudioUnit registerSubclass:asComponentDescription:name:version:]`), then used `AVAudioUnit.instantiate(with:options:)` from Swift.

---

## Working diff (reverted from the branch — reproduce in Sprint 5 M1)

`Sources/AudioDSP/include/AudioUnitBridge.h` — add to the `extern "C"` block:
```c
void registerAdaptiveAudioUnitSubclass(void);
AudioComponentDescription adaptiveAudioUnitComponentDescription(void);
```

`Sources/AudioDSP/AudioEngine/AUAudioUnit.mm` — add bus-array ivars; in `-init` create the
kernel + render block + a stereo input/output `AUAudioUnitBusArray`; override `-inputBusses` /
`-outputBusses`; in `allocateRenderResources` only `_kernel->initialize(...)` (do **not**
re-create the kernel); add the two C-ABI registration functions. (Full diff captured in the
session; ~70 lines.)

> NB: the spike used `error:nil` on bus init, created the render block in both `-init` and
> `allocateRenderResources` (the latter is now redundant), and did not re-negotiate format on
> allocate. Sprint 5 must do these **properly** with the RT-safety + format-change review
> (Gap-1 fix must preserve "no `self`/weak/alloc/lock on the render thread").

---

## What this means for the Sprint 5 plan

- **AU-graph wiring is low-risk, not unknown** — the engine accepts, connects, and renders the
  custom AU. Remaining work is well-trodden v3-AU boilerplate + careful RT-safety, not research.
- **Control is whole-`TargetState`, not per-parameter** — `setAUParameter` is a stub; live EQ
  control flows through `publishTargetState(auUnit, &targetState)`. Sprint 5's "Realizer" must
  build a `TargetState` (EQ coeffs etc.) and publish it; there is **no** C-ABI to construct a
  `TargetState` from Swift yet (it's a C++ struct) — that bridge is a Sprint 5 task.
- **Format**: standard stereo float @ 48 kHz connected directly; matches the existing
  `AudioEngineBridge` graph format. Device-driven sample-rate changes need `allocateRenderResources`
  re-init (deferred / handled in M1).
- The existing mixer **tap-based meters** (Sprint 4) keep working unchanged; the new
  **after-DSP spectrum tap** attaches on the AU's output bus.

## Reproducing the spike
Throwaway harness was `Sources/SpikeAUGraph/main.swift` (+ pure-C `SpikeBridge.h`) as an
`.executableTarget`, run with `swift run SpikeAUGraph`. It: registers the subclass, instantiates
via `AVAudioUnit.instantiate`, attaches + connects `player → AU → mainMixer`, enables
`.offline` manual rendering, schedules a 1 kHz sine, renders in 512-frame blocks, and asserts
all blocks `.success` + output finite/non-silent/peak-preserved. Recreate from this doc if needed.
