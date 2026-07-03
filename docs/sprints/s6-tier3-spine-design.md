# S6 Tier-3 — DSP Spine Rework: Design & Implementation Plan

**Document ID:** S6-TIER3-DESIGN-001
**Version:** 0.2 — incorporates the C++/RT + DSP expert reviews (2026-06-19). For founder sign-off, then implementation.
**Status:** DESIGN (reviewed). Build **carefully, correctness over speed** (founder directive). Founder decisions: (1) Realizer owns feed-forward control; Loudness measurement→makeup feedback stays a documented module-local loop. (2) Build all four (Realizer/RMW, steerable intensity, RtSwappableResource, GaplessController) now.

> **v0.2 changelog (from review):** intensity blend moved **before** Loudness+Limiter (was after — voided the −1 dBTP ceiling + mis-measured loudness); **equal-power** crossfade (was linear); endpoint bit-exactness now via **settled-ramp hard branches** (lerp doesn't collapse bit-exactly); **planar per-channel** dry copy; Realizer holds `_currentState` in a **`shared_ptr`-owned C++ object** with queue-draining teardown (fixes a UAF); coalescing slot specified concretely; **GaplessController protocol already exists** → build the shared **conformance test suite** instead, and verify position-re-zero parity.

---

## 0. Why this is lower-risk than the review's framing implied

A canonical state + read-modify-write **already exists**: `AdaptiveSoundAU` holds `TargetState _currentState`, and `publishEQParams:` does `_currentState.eq = …; sequenceNumber += 1; publishState` — an RMW that preserves the other modules' fields (`AUAudioUnit.mm:210-214`). So the param-clobber problem is already solved for the **single-surface, single-thread** case. Tier-3 makes ownership **structural** (off-main serial owner + intent API), adds the steerable-intensity primitive, factors the RT swap, and pins the gapless contract with tests.

---

## 1. The Realizer (3a) — single-producer, off-main control owner

### Design
A **C++ Realizer object owned by a `shared_ptr`** (the same ownership discipline as `_kernel`), **not** an ObjC ivar:

- It **owns `_currentState`** (moved out of the `@interface` ivar into the Realizer) and a `shared_ptr<DSPKernel>` (or a back-reference to publish through). This makes "only the Realizer touches `_currentState`" **structural**, not conventional — retiring the load-bearing single-producer comments at `DSPKernel.mm:70` / `EQModule.h:36`.
- A dedicated **serial `dispatch_queue`** (`com.adaptivesound.realizer`, off-main/off-RT). It is the **sole** caller of `publishTargetState → EQModule::publishCoefficients + DoubleBufferSnapshot::publish`.
- C-ABI entry points **post intents**, capturing a **`shared_ptr` to the Realizer (never `self`)** so a teardown with intents in flight keeps the Realizer + kernel alive until the queue drains:
  - `publishEQBandGains(...)` → set the pending-EQ slot + post a drain.
  - new `publishIntensity(float)` → set the pending-intensity slot + post a drain.
- **Teardown:** `AdaptiveSoundAU -dealloc` (or an explicit `shutdown`) must **quiesce the queue** — `dispatch_sync(realizerQueue, ^{})` (a draining barrier; `dispatch_suspend` is NOT sufficient) — before dropping its `shared_ptr`, so no queued block runs after free. (Fixes review §1.1 UAF.)

### Coalescing (review §1.3 — concrete)
`EqGains` is `float[31] + sampleRate` → **not** atomic-representable, so no `std::atomic` slot. Instead, **per-intent-kind slots owned by the Realizer** (written on the control thread that calls the C-ABI — the `@MainActor`, the single control thread per `AudioUnitRegistrationBridge.h:63`):
- `pendingEqGains` (plain `std::array<float,31>` + `bool eqDirty`), `pendingIntensity` (`float` + `bool intensityDirty`).
- Each entry point writes its slot and posts a drain block **only on a clean→dirty transition**; the drain reads-and-clears the dirty slots, recomputes only what changed (EQ dirty → `computeBiquadCascade` **off-main, here**), RMWs `_currentState`, bumps `sequenceNumber`, publishes once. This gives true "compute once per burst" and **never drops an interleaved intensity intent** (separate slot). If multiple control threads ever call, guard the slots with a small off-RT mutex (not an atomic).

### Feed-forward vs feedback (founder decision 1; both reviewers endorse)
- **Realizer = sole producer of feed-FORWARD control** in `TargetState` (EQ coeffs, intensity, clarity/loudness targets, BRIR pose, limiter ceiling).
- **Measurement-driven FEEDBACK stays module-local:** `LoudnessModule` keeps measuring on its own worker and applying `makeupGainLinear` via its atomic (`LoudnessModule.h:21-28`). Routing it through the control queue would inject latency and break the single-producer rationale. Documented invariant: *"TargetState carries feed-forward control produced solely by the Realizer; modules may run their own measurement-driven feedback loops for their own derived gains."*

### Ordering note (review §1.4)
`publishChannelLayoutTag` stays a direct call to the loudness worker (not through the Realizer). Document that the **feed-forward (Realizer) and loudness side-channel planes are unordered w.r.t. each other** (they target different state); within each plane, order is preserved.

### Intensity surface reconciliation (review §1.5)
`AUParameterID::Intensity = 2` + `setAUParameter` is a dead stub (`AUAudioUnit.mm:357`). Decision: route the **new `publishIntensity` C-ABI** as the single intensity surface; leave `setAUParameter(Intensity,…)` returning false with a comment pointing to `publishIntensity` (don't create two contradictory surfaces).

---

## 2. Steerable wet/dry intensity (3b) — corrected topology

### Corrected signal flow (review DSP-Issues 1/2/3, C++ §2.5)
The blend sits **before Loudness+Limiter** so the limiter guards the final output and loudness measures what the listener hears:

```
if (settled && x == 0)  → early return            // bit-exact bypass (today's path; golden master)
dry ← per-channel planar copy of input            // BEFORE any module runs
EQ → Clarity → BRIR  (in-place on ioData = "wet")
if (settled && x == 1)  → (no blend)               // bit-exact: pure in-place chain (golden master)
else  per channel:  out = dry + r·(wet − dry)      // r = equal-power ramped wet gain (see below)
Loudness  (measures the BLENDED signal → makeup converges on the actual output)
Limiter   (guards the BLENDED output → −1 dBTP ceiling always holds)
```

**Semantic:** intensity scales the **coloration** stages (EQ/Clarity/BRIR); **Loudness normalization + true-peak Limiter always apply** whenever not fully bypassed (x>0). x==0 is the bit-exact "pure/off" bypass. *(Founder: flag if you want a different intensity semantic — this is the loudness-safe interpretation both reviewers require.)*

### Equal-power crossfade (review DSP-Issue 2)
Linear blend dips ~3–6 dB at x=0.5 for decorrelated wet/dry. Use **equal-power**: `wetGain = sin(x·π/2)`, `dryGain = cos(x·π/2)`. Compute per **block** from the ramped x (per-sample sin/cos unnecessary; 32 ms ramp ⇒ block granularity inaudible), or build a per-sample ramp vector and derive gains. Implement the blend as the lerp `out = dry + r·(wet − dry)` (`vDSP_vsub` then `vDSP_vma`) where `r = wetGain` and the dry term is `(1−... )` folded in — i.e. `out = dryGain·dry + wetGain·wet` via two `vDSP_vsma`/`vDSP_vmul`+`vDSP_vadd`. (Pick the 2-op form; document it.)

### Endpoint bit-exactness (review §2.3 — BLOCKER)
A ramped x approaches 0/1 **asymptotically**; `dry + 1·(wet−dry)` is **not** bit-equal to `wet`. So the endpoints MUST take **hard branches gated on "settled"** (ramp within ε of target AND target ∈ {0,1}), exactly like EQ's settled check (`EQModule.mm:172`):
- **settled at 0** → early return (no decode, no copy) — today's bypass.
- **settled at 1** → run the chain fully in-place, **no blend code** — today's path → golden master `0xE7267654BA01D315` unchanged.
- **anything else** (including descent 0.5→0 mid-ramp, ascent →1 mid-ramp) → the dry-copy + blend path. Never early-return mid-ramp (would click).

### RT-safety details (review §2.1, §2.4, DSP-Issue 6)
- Dry scratch is **planar**, sized `maxFrames_ × kMaxChannels`, allocated in `initialize()`; channel `ch` at `dry + ch·maxFrames_`. Copy/blend **per channel** (`cblas_scopy`/`vDSP_mmov` of `frames` floats from `block.channel(ch)`), never one block memcpy (buffers are non-interleaved, `AUAudioUnit.mm:125`). Assert `frames ≤ maxFrames_`.
- Dry scratch and ABL buffers never alias; dry copy happens before EQ mutates in place. The blend is in-place into the wet buffer (vDSP permits; dry is distinct).

### Ramp init (review DSP-Issue 5)
`ParameterRamp` starts at `current=0`. With default `intensity=1.0`, an unsnapped ramp would fade in from silence over ~160 ms on launch/track-load. **Snap the intensity ramp to the initial `intensityLinear` in `initialize()`** (mirrors LoudnessModule's makeup-ramp snap, `LoudnessModule.h:89`).

> This provides the **kernel primitive**; UI wiring of the Reimagine knob is S12/S17.

---

## 3. RtSwappableResource<T> (3c) — extract EQ's triple-atomic swap

Extract EQModule's `active_/pending_/toRelease_` pattern (`EQModule.h:65-67`) into a template. **Atomic slots stay raw `std::atomic<T*>`**; RAII (`unique_ptr<T>`) appears only at the API edges (`publish(unique_ptr<T>)`, and in `reclaim()`/dtor where a raw ptr is rebound to a `unique_ptr` to free). T's dtor frees the resource (e.g. a RAII wrapper over the opaque `vDSP_biquad_Setup` calling `vDSP_biquad_DestroySetup`).

### Per-op memory ordering (review §3.1 — make explicit, don't blanket acq_rel)
- `active()` RT read: `load(acquire)` — **load-bearing**; pairs with the producer's release so the RT thread sees fully-constructed contents.
- `adopt()` RT: `pending_.exchange(nullptr, acquire)` (acquire the new resource's contents) + `active_.store(new, release)` (publish to future `active()`) + deposit old into `toRelease_` (`release`; only the pointer is handed off).
- `publish()` off-RT: store into `pending_` is the **`release`** that pairs with adopt's acquire.
- `reclaim()` off-RT: `toRelease_.exchange(nullptr, acquire)` then free.
- Keep `static_assert(std::atomic<T*>::is_always_lock_free)`.

### Single-pending leak window (review §3.2 — acknowledge + tie to Realizer)
If the producer publishes twice before the RT adopts once, the displaced setup is intentionally leaked (`EQModule.mm:131-132`). Tolerable for EQ; **worse for BRIR** (large kernels). Resolution: the resource is documented **single-pending — the producer must not outrun the RT adopt**, which the **Realizer's coalescing guarantees** (a burst collapses to one publish). Cross-reference 3a↔3c in the code comments. (Optionally expose the orphan to the caller for a future BRIR policy.)
- **No ABA** (we only `exchange`, never CAS-compare) — note it so nobody "fixes" it with tagged pointers.
- **EQ's delay-state preservation across swaps stays in EQModule** (`EQModule.mm:135-139`) — it is module-specific, NOT part of the generic template. The template swaps the resource; `delays_` stays in EQModule.
- Migrating EQ is the only touch of working RT code → gate on EQ FR + bypass + golden master unchanged. Pure mechanical wrap.

---

## 4. GaplessController (3d) — the protocol already exists; build the contract tests

### Reframe (review §4.2)
The Swift `AudioPlaybackEngine` protocol **already declares** `setNextTrack(_:) async`, `trackTransitionCount() -> UInt64`, `playbackEnded() -> Bool` with neutral defaults (`AudioPlaybackEngine.swift:31-41,78-88`), and both paths conform. **Do not add a second protocol.** The genuine gap is an **executable shared conformance test suite** asserting the behavioral contract against **both** the Enhanced bridge and the Pure C-ABI:
- arm → seam → transition-count increments by exactly one per seam; `setNextTrack(nil)` cancels the on-deck; end-of-queue signals `playbackEnded`.
- **position re-zeroes at seam** — assert on **both** paths.

### Two real invariants the suite must pin (reviews §4.3, §4.4 — may surface bugs)
- **Position-re-zero parity (§4.3, HIGH):** Pure re-zeroes per track at the seam (`PureModeBridge.h:137-140`); the Enhanced path may report *cumulative* position across the seam. If they diverge, that's a **bug to fix**, not just document. Required assertion.
- **Poll-reaps-source side effect (§4.4):** `pureModeEnginePollTrackAdvance` *also reaps the retired source off-RT* (`PureModeBridge.h:156-159`) — so `trackTransitionCount()` is **not** a pure observer on Pure; it must be polled regularly or decode threads leak. Encode this as an explicit contract invariant; Enhanced has no such coupling — reconcile or document the asymmetry.

Additive only (tests + maybe a thin adapter) — cannot regress the two existing implementations. Extend the existing `PureGapless*` null tests.

---

## 5. Implementation order (small, independently gate-verified commits)

Each sub-step: builds, C++ null-test 82/0 + **golden master unchanged**, clang-tidy + swiftlint clean, separate commit. **Stop and report if any golden master changes.**

1. **3c — RtSwappableResource<T>** + migrate EQ. Lowest-risk, self-contained, no behavior change. Gate: EQ FR + bypass + golden master unchanged.
2. **3a — Realizer.** `shared_ptr`-owned C++ object owning `_currentState`; serial queue; per-intent-kind coalescing slots; cascade off-main; sole publisher; queue-draining teardown. Re-point `publishEQBandGains` → EqGains intent; add `publishIntensity`. Gate: EQ still drives live (FR test), golden master unchanged.
3. **3b — steerable intensity** (corrected topology §2): planar dry copy, blend before Loudness+Limiter, equal-power, settled-gated endpoints, snapped ramp. Gate: settled x∈{0,1} byte-identical (golden master); new crossfade tests (below).
4. **3d — GaplessController** shared conformance suite + the two invariants; fix any position-re-zero divergence found.

> **Cross-coupling to remember:** 3c's single-pending safety *depends on* 3a's coalescing — note it in both even though 3c ships first.

After all four: update [sprint-plan.md](sprint-plan.md) (S6 complete; spine ready) + the S7 verification-gap stories.

---

## 6. Verification plan

- **Golden master `0xE7267654BA01D315` must not change** at any sub-step. Add an explicit test: *set intensity 0.5 then 1.0, run until the ramp settles, assert byte-identical to baseline* — proves the ramp converges into the hard in-place branch (review cross-cutting).
- **New intensity null-tests:** endpoints bit-exact (settled); **true-peak ≤ −1 dBTP at x ∈ {0.1,0.25,0.5,0.75,0.9}** on a limiter-saturating signal (this is the regression guard for the moved-blend fix); **LUFS monotonic in x** (x=0 → dry LUFS, x=1 → target, intermediate between); **equal-power conformance** (correlated wet/dry RMS at x=0.5 within 0.5 dB of −3 dB, not −6 dB); no NaN/denormal; fast 0→1 step settles within ~5τ without clipping.
- **Realizer:** multi-surface RMW (EQ→intensity→EQ → no field clobber, sequenceNumber monotonic); teardown with intents in flight does not UAF (drain barrier).
- **RtSwappableResource:** publish/adopt/reclaim under simulated RT/off-RT interleaving — no leak (beyond the documented single-pending orphan) / no UAF / no double-free.
- **GaplessController:** shared conformance against both paths incl. position-re-zero parity.
- **`-fno-exceptions`:** `static_assert(is_trivially_copyable)` on each intent struct (matches `TargetState`).
- clang-tidy + swiftlint (whole-file) on every touched file; fix every issue. I run all gates myself.

---

## 7. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Realizer async publish + teardown UAF | `shared_ptr`-owned Realizer; blocks capture the shared_ptr; dealloc drains via `dispatch_sync` barrier. |
| Endpoint golden-master regression from ramp | Hard in-place / early-return branches gated on **settled** target ∈ {0,1}; never lerp-collapse. Explicit settled-ramp bit-exact test. |
| Blend defeats −1 dBTP ceiling | Blend **before** Loudness+Limiter; TP-at-intermediate-x gate. |
| Midpoint level dip | Equal-power (sin/cos) law; equal-power conformance test. |
| EQ→RtSwappableResource regression | Pure mechanical wrap; FR + golden master gate; ship it first in isolation. |
| BRIR large-kernel leak via single-pending | Documented single-pending + Realizer coalescing guarantees no outrun; revisit orphan policy at S18. |
| Position-re-zero divergence between paths | Conformance suite asserts parity; fix if divergent. |
| Can't runtime-test concurrency/audio | Offline gates + careful review; founder by-ear/by-hand verifies (knob sweep, device switch). |

---

**Maintained by:** AdaptiveSound team · **Reviewed by:** modern-cplus-plus-expert + audio-dsp-agent (2026-06-19) · **Feeds:** [s6-architecture-review-findings.md](s6-architecture-review-findings.md) (Tier 3), [sprint-plan.md](sprint-plan.md) (S6 gate).
