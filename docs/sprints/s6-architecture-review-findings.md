# S6 — Technical Architecture Review: Findings & Fix List

**Document ID:** S6-ARCH-REVIEW-001
**Date:** 2026-06-19
**Status:** Review complete — findings for founder triage; fixes pending scope decision.
**Method:** 4-discipline read-only review of the shipped codebase (no edits): system architecture (architect-reviewer), C++ RT-safety & lock-free correctness (modern-cplus-plus-expert), Swift concurrency & lifecycle (swift-expert), DSP correctness & gain staging (audio-dsp-agent). Every finding is grounded in `file:line`.
**Gate role:** This is the S6 deliverable. Per [sprint-plan.md](sprint-plan.md), no feature sprint (S7+) starts until the agreed fixes land and the C++ gate is green.

---

## Executive summary

The shipped engine is, in the reviewers' words, **"unusually careful and well-documented"** — the lock-free transport, the C-ABI boundary, the path-selection/fallback model, and the Pure-path bit-exactness are production-quality. The review found **one real current bug**, **a cluster of Swift concurrency races on the device-disconnect path**, **a few latent RT memory-safety exposures**, and — most importantly — **a strategic finding: the DSP "spine" is not actually ready to carry the Phase 2 adaptive vision.**

The headline is not "the code is bad." It's: **before we build eight sprints on this foundation, fix the one live bug, close the concurrency races, harden the RT edges, and decide the spine architecture — because Phase 2 will hit the spine gaps on day one.**

---

## ★ The strategic finding — the DSP spine is not Phase-2-ready (architect lens, P1)

The architecture docs describe an **Arbiter → Realizer → `TargetState` bus → kernel** spine. The **downstream half is real and excellent** (POD `TargetState`, `DoubleBufferSnapshot` SPSC bus, RT consumer — correct acquire/release, zero-cost on ARM64). **The producer half does not exist**, and there are three structural gaps Phase 2 will hit immediately:

1. **No off-RT Realizer/Arbiter.** EQ realization (the ~200-line greedy biquad fit) runs **synchronously on `@MainActor`** on every slider event (`EQViewModel.swift:101` → `publishEQGains` → `publishTargetState`). Fine for EQ math today; fatal for an Arbiter fusing loudness + content analysis + perceptual targets + BRIR kernel selection. *The off-RT worker box on the diagram was never built.*
2. **`publishTargetState` is a full-struct overwrite with no read-modify-write** (`DoubleBufferSnapshot.h:20-25`, `DSPKernel.mm:65`). It works today only because there is coincidentally **one** producer (EQ). The moment a second control surface exists (intensity, clarity toggle, BRIR azimuth — all Phase 2), each publish **clobbers** the others' fields. There is no canonical off-RT `TargetState` to read-modify-write against.
3. **The one adaptive feature already bypasses the bus.** `LoudnessModule` routes its measurement-derived makeup gain through a **module-local** atomic + its own off-RT thread + its own double-buffer (`LoudnessModule.h:21-25,134-135,160`) — *specifically to keep `publishTargetState` single-producer*. This is the canary: every Phase 2 adaptive stage faces the same forcing function, so we'd get N bespoke side-channels instead of one spine.

Plus: **`process()` is in-place with a binary 0/1 bypass** (`DSPKernel.mm:106`) — it structurally **cannot express a steerable wet/dry intensity** (a headline Phase 2 capability); and **Clarity/BRIR are empty inline no-ops** (`ClarityModule.h:14-19`, `BRIRModule.h:14-19`) with none of the off-RT setup-swap scaffolding BRIR convolution needs.

**Implication for the plan:** Phase 2 is **not** "wire up stubs onto a ready spine." It needs a **foundation sprint** — build the Realizer tier (off-RT, single-producer, owns the canonical `TargetState`, read-modify-write), resolve bus-vs-side-channel (hoist Loudness's worker into the Realizer, or formally adopt per-module workers), and define the steerable-intensity (dry/wet crossfade) primitive — **before** S15/S16/S17 depend on the in-place assumption. This should become the first sprint of Phase 2 (a new S14.5 / re-scoped S15 enabler).

---

## P1 — Fix before feature work

| # | Lens | Location | Issue | Consequence | Fix |
|---|---|---|---|---|---|
| **P1-A** | DSP | `EQModuleCoefficients.h:266-271` | **Incomplete Schur-Cohn biquad stability check** — tests only `|a1| > 1 + a2`, missing the lower-half triangle (`1 - a2 - |a1| > 0`). | **Real current bug:** high-frequency EQ bands near Nyquist (e.g. 20 kHz @ 44.1 kHz) can silently fall back to identity — *the band does nothing* — with no diagnostic. | Replace with the full three-condition test: `|a2| < 1` AND `1 + a2 - |a1| > 0` AND `1 - a2 - |a1| > 0`. Add a stability sweep test (→ S7). |
| **P1-B** | Swift | `+PureModeDeviceMonitor.swift:75-92`, `+ConfigChange.swift:31` | **Device-disconnect double-handler race.** A single BT/USB disconnect fires *both* the alive-listener (`pauseForDeviceLoss` on a global queue, writing `enhancedPlayIntent` off its owning `resampleQueue` and tearing down the engine) **and** `AVAudioEngineConfigurationChange` (`reestablishEnhancedAfterConfigChange` on `configChangeQueue`) — concurrently, racing on `enhancedPlayIntent`, `cachedSignalPath`, and `stop()` vs `start()`. | Most likely real-world **silent-dead playback / `-10875` storm** — the disconnect path is exactly what the `interrupted` flag guards, but that flag is itself unsynchronized (P1-C). | Route `pauseForDeviceLoss` onto `configChangeQueue` (serialize against re-establish); write `enhancedPlayIntent` via `resampleQueue.sync` like every other site; establish happens-before between "interrupt published" and "re-establish reads it." |
| **P1-C** | Swift | `AudioEngineBridge.swift:75,84,92,65`; many | **Unsynchronized shared mutable state** read/written across MainActor (20 Hz poll) + `configChangeQueue` + `resampleQueue` + CoreAudio listener queues: `cachedSignalPath`, `enhancedPositionBaseSeconds`/`lastKnownEnhancedPositionSeconds`, `currentDeviceID`, `lastFileURL`. Comment says "polled lock-free" but there's no atomic/double-buffer. | Torn reads → wrong UI state, **missed/duplicated device-loss interrupt**, wrong resume position after a config change coinciding with a poll/seam. Hard error under Swift 6. | Confine each to one queue, or guard with one `os_unfair_lock` (or migrate the bridge to an `actor` with `nonisolated` lock-free readers — see structural fix S below). |
| **P1-D** | C++ | `HALOutputEngine.mm:806-812,728-745` | **HAL render-format RT memory-corruption exposure:** `convertFloatToNative` writes `buf.mData` **without bounding by `buf.mDataByteSize`**; the 7 `rf*` format fields are **non-atomic, multi-word, read on the RT thread, written on the control thread**. | Low-probability today, **high severity**: on a device format change under load, a torn rf-read or unbounded convert → **heap/buffer overrun on the audio thread**. | Bound the convert by `mDataByteSize`; publish the render-format as a small POD through the existing `DoubleBufferSnapshot` (idiomatic, already in-tree). |

---

## P2 — Should-fix (hardening + maintainability)

| # | Lens | Location | Issue | Fix |
|---|---|---|---|---|
| **P2-A** | C++ | `GaplessSource.cpp:101-140,248-251` | `freeSlotForArm` is safe **only while `armedNext_ == nullptr`** — load-bearing but **undocumented**; one refactor from a `unique_ptr` data race / UAF on the RT thread. And `nxt->source` is dereferenced at the seam with no null guard. | Add `assert(armedNext_.load() == nullptr)` + comment at `freeSlotForArm`; add a one-line `nxt->source == nullptr` guard at the seam (RT-path insurance). |
| **P2-B** | Swift | `+Playback.swift:9,176,224`; `+PureMode.swift:150` | All transport (`startAudio`/`stopAudio`/`seek`/`setParameter`/`shutdown`/`selectDevice`) runs on the **concurrent** `DispatchQueue.global()` — nothing serializes graph mutations against each other (e.g. `seek` reading `activePath` while `stopAudio` writes it). | Introduce one dedicated **serial `engineQueue`** for all transport/graph mutation. Highest-leverage structural fix; subsumes part of P1-C. |
| **P2-C** | Swift | `AudioViewModel.swift:191-204`; `AudioEngineBridge.swift:286-342` | `shutdown()` fires `stopPlayback` and `engine.shutdown()` as **unordered** Tasks → can tear down `avEngine`/`loudnessMeter`/`pureEngine` while the other is mid-flight → **UAF on quit**. | `await` `stopPlayback` before `engine.shutdown()`; make `currentLoudness()`/`currentSignalPath()` nil-safe under the P1-C lock. |
| **P2-D** | DSP | `LoudnessModule.h:50`, `EQModuleCoefficients.h:71,95` | **Headroom budget unverified.** `masterGainLinear` is always `1.0` (no cascade-level trim); stacked EQ (+12 dB, up to 10 biquads, no global clamp) + makeup (+12 dB) can push the limiter into **sustained heavy gain-reduction**. | Add a cascade-level peak audit in `computeBiquadCascade()` → write a normalizing trim into `masterGainLinear`; document the budget in `AudioConstants.h`. |
| **P2-E** | DSP / C++ | `GaplessSource.cpp:250-253` | At the seam, if the armed-next ring isn't pre-buffered, `pullFloat` returns 0 for track B → **one buffer of silence** at the transition (not sample-accurate under heavy decode latency). | Pre-buffer guard / `!nxt->source->exhausted()` pre-check before adopting the armed source. |
| **P2-F** | DSP | `DSPKernel.mm:102-106` | The `intensityLinear == 0` bit-exact bypass is **in-place-only**; no assertion stops a future Phase-2 tap caller passing separate in/out buffers → **silent corrupted output**. (Ties to the steerable-intensity primitive in ★.) | Add an assert / API contract; or copy input→output when buffers differ. |
| **P2-G** | Arch | `LoudnessModule.h:30` | **Layering inversion:** a DSP stage `#include`s `EQ/EQModule.h` just to borrow `ParameterRamp` (shared infra misfiled as EQ-private). | Move `ParameterRamp` to `include/ParameterRamp.h`. Low-effort. |
| **P2-H** | Arch | `GaplessSource.cpp` vs `+Gapless.swift` | **Gapless is fully duplicated** across paths (Pure lock-free C++ vs Enhanced queue-serialized Swift, 4 sub-paths) — every future gapless behavior (crossfade, cue points, ReplayGain-at-seam) must be built/tested **twice**. Position semantics also diverge. | Don't unify the *mechanism*; unify the **contract**: a single `GaplessController` protocol + one **shared conformance test suite** run against both. |
| **P2-I** | Swift | `AudioViewModel+SpectrumTimer.swift:47-57` | Auto-advance advances `selectedTrackIndex` by **one per 20 Hz tick** even if `trackTransitionCount()` jumped >1 → drift to the wrong track with very short files / UI stalls. | Advance by the actual delta, or have the engine report the current on-deck identity instead of relying on the VM mirror. |

---

## P3 — Style / robustness / Swift-6 readiness (selected)

- **Swift 6 strict-concurrency:** `AudioEngineBridge` is a non-Sendable class shared across the MainActor VM and many background queues — a wall of errors under Swift 6 today (compiles only because the package is 5.9, no strict-concurrency flag). The strategic target: make the bridge an `actor` (or wrap all shared state behind one) with `nonisolated` lock-free readers — **this single change subsumes P1-B, P1-C, P2-B, P2-C**. (swift-expert P3-1)
- Swallowed errors on gapless-roll failure (`+Gapless.swift:172-178`) — `try?` discards the error and never sets `gaplessPlaybackEnded`, so the VM polls a stopped engine. Set the ended flag on the failure path. (P3-3)
- `Timer.scheduledTimer` poll may outlive teardown if `onDisappear` doesn't fire on quit (window-close vs quit) — also invalidate on app-termination / drive from a cancellable `.task{}`. (P3-4)
- DSP P3s: FTZ called on the control thread in `initialize()` is a no-op (render thread + worker already set it correctly); float `== 0.0F` intensity check is safe today but an epsilon threshold is more robust; EQ delay-state preserved across coefficient swaps can cause a brief transient on big gain flips (acceptable).
- `std::nothrow` on `pureModeEngineCreate` is illusory under `-fno-exceptions` (inner `make_unique` aborts on OOM) — drop the pretense or construct nothrow. (C++ P2-4)

---

## Verification gaps → fold into S7 (DSP-gate hardening)

The null-test gate only proves the **intensity-0 bypass** is bit-identical. Not covered (and should become S7 stories):
- **True-peak ceiling enforcement** — 997 Hz @ 0 dBFS → output ≤ −1 dBTP (libebur128 TP meter).
- **Schur-Cohn stability sweep** — every {44.1/48/96 kHz × gain ∈ ±3/±6/±12 dB × 31 bands}: assert all poles strictly inside the unit circle; **no band silently drops to identity** (regression guard for P1-A).
- **Near-Nyquist EQ** — +6 dB on the 20 kHz band @ 44.1 kHz → spectrum shows the boost.
- **LUFS convergence** — −20 LUFS program → makeup converges to target ±0.5 LU within ~10 s, TP stays ≤ −1 dBTP.
- **Gapless seam sample-count** — two finite sources → exactly `durA + durB` frames, no zero-pad between.
- **TSan stress harness** for the param bus + `GaplessSource` seam (hammer publish/acquire and arm/clear/seam from contending threads) — the safety net the Realizer work needs.

---

## Recommended fix triage (for founder decision)

**Tier 1 — fix now (contained, high-value, low-risk):** P1-A (Schur-Cohn — the one live bug), P1-D (HAL convert bounding), P2-A (GaplessSource assert + seam null-guard), P2-G (move `ParameterRamp`), P2-C + P3 gapless-roll error surfacing. *Small, mechanical, each gate-verifiable.*

**Tier 2 — structural concurrency hardening (one focused effort):** the Swift **serial `engineQueue` + single lock** consolidation that retires P1-B, P1-C, P2-B, P2-C together (the architect's and swift-expert's shared top recommendation). Medium effort; the right time is now, before feature surface grows. The full `actor` migration (P3-1) is the larger version — can be staged.

**Tier 3 — spine architecture (informs the plan, not a bug-fix):** the ★ finding. Build the **Realizer tier** + resolve bus-vs-side-channel + define the **steerable-intensity** primitive as a **Phase 2 foundation sprint** (new enabler before S15/S16). Also the `GaplessController` contract (P2-H) as gapless features land. *This reshapes Phase 2 sequencing in [sprint-plan.md](sprint-plan.md).*

**→ S7:** the verification gaps above.

---

## What is correct and should be preserved (for the record)

The C-ABI boundary discipline (`PureModeBridge.h` — pinned enum ordering, opaque-handle ownership, ABI-stable bool); the path-selection/fallback model (`+PureMode.swift` — CoreAudio-free policy decides, clean fallback to Enhanced, mutual exclusivity by construction); the downstream lock-free transport (`DoubleBufferSnapshot`, POD `TargetState` — textbook acquire/release); the `SpscRing` rigtorp design; the partial-frame carry across pulls; the `resampleQueue.sync` deadlock guard + generation/epoch cancellation; the RT tap discipline (no alloc/lock on the audio thread); the master-gain/limiter ordering and Pure-path bit-exactness (both verified **correct** — the prior pipeline-review's suspected gain-after-limiter bug **does not exist**).

---

**Maintained by:** AdaptiveSound team · **Feeds:** [sprint-plan.md](sprint-plan.md) (S6 gate, S7 QA stories, Phase 2 foundation sprint)
