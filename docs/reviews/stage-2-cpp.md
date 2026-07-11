# Codebase review — Stage 2: C++ quality

**Scope:** all C++/Obj-C++ under `Sources/AudioDSP` + `Sources/AudioDSPTestBridge` (~11K LOC).
**Theme:** architectural elegance · reuse · best practices — at the *language* level (RAII,
ownership, RT-safety, headers, modern C++20/23). DSP math (Stage 1) and pure DSP-architecture/reuse
(Stage 1) excluded.
**Method:** two independent SMEs (ownership/lifetime/RT-safety lens + modern-idiom/API/header lens),
red-teamed by *the-fool*, reconciled here.

---

## Verdict

The C++ **core is safe and genuinely well-crafted** — both SMEs independently confirmed it. The
RT primitives (`RtSwappableResource`, `DoubleBufferSnapshot`, `SpscRing`), the RAII wrappers
(`VDSPBiquadSetup`, the FFmpeg/ExtAudioFile backends, `std::jthread` ordering in LoudnessModule),
`MultichannelView`, the AU ARC-bridging, and the C-ABI opaque-handle discipline are all praised.

The findings are **one latent correctness hazard** and a pervasive **consistency-drift** theme:
individually-excellent pieces, but conventions not applied uniformly across the tree (three
header-guard styles, `.mm`/`.cpp` split not by Obj-C-ness, `noexcept` on some C bridges not others,
two `kMaxBiquads`, `M_PI` vs `std::numbers`). Same meta-shape as Stage 1's reuse theme: good
primitives, inconsistent application.

---

## Findings (ranked, merged)

| # | Sev | Area | Finding |
|---|-----|------|---------|
| 1 | **HIGH** | DRY/RT-safety | `kMaxBiquads` defined **twice** (`TargetState.h:12` namespace-scope, `EQModuleCoefficients.h:37` class-scope), both `10`, no `static_assert` linking them. `EQParams::biquads` is sized by one; the fit/copy loop is bounded by the other. Bump one → silent buffer overrun on data published to the RT thread. |
| 2 | MED | handle-ownership / race | `CoreAudioDevice` listener block **registered, never removed** (`:59-106`); the "can't remove block listeners" comment is **false**; single-listener statics raced on the concurrent dispatch queue. Latent — **zero callers today** (Swift owns this correctly). Fix: delete the dead API. |
| 3 | MED | concurrency (off-RT) | `Realizer` coalescing slots (`Realizer.mm` `pendingEq/Intensity/Crossfeed`) are **non-atomic PODs written on the control thread, read on the serial-queue thread** → data race under a sustained slider drag. Header admits writes are "un-guarded". Fix: off-RT `std::mutex`. |
| 4 | MED | api-design / ABI | `AUDIODSP_C_NOEXCEPT` applied to only **2 of 4+** C-ABI bridge headers (`MetadataBridge`, `PureModeBridge` have it; `AudioUnitBridge`, `DeviceBridge`, `AudioUnitRegistrationBridge`, `EQTestBridge` don't). Their bodies call throwing C++ → an exception unwinding into Swift is UB. Apply uniformly + hoist the macro to one home. |
| 5 | MED | header-hygiene | Header guards inconsistent **three ways**: 14 `#pragma once` vs **21** `#ifndef`; DSPKernel.h's comment claims `#pragma once` "matches the plurality" (false — `#ifndef` is the plurality); and the bare unnamespaced guards it calls "collision-prone" are still everywhere (`LIMITER_MODULE_H`, …). Standardize (recommend `#pragma once`) + fix the comment. |
| 6 | MED | objcpp-boundary | **7 pure-C++ TUs compiled as `.mm`** (`DSPKernel`, `EQModule`, `LoudnessModule`, `CrossfeedModule`, `SpatialRenderKernel`, `ChannelLayoutDecoder`, `EQTestBridge`) — zero Obj-C. Forces the Obj-C++ frontend and keeps them out of the CoreAudio-free unit-test harness. The project already sets the opposite precedent (`GaplessSource.cpp`, `PureModeFormat.cpp`, `PureModeBridgePolicy.cpp` split out *for this reason*). Rename to `.cpp`. |
| 7 | LOW | lifetime | `PureModeSession` declares `engine` before `gapless` → reverse-of-safe destruction; safe only because every path calls `engine->stop()` first (nulls the raw `source_`). Reorder to make it structural. |
| 8 | LOW | noexcept | `startDecodeThread()`/`seek()` are `noexcept` but `std::thread`'s ctor can throw → `std::terminate` on thread-exhaustion. Document the stance or drop `noexcept` + return failure. |
| 9 | LOW | correctness | `cfStringToStdString` sizes the buffer by UTF-16 length but decodes UTF-8 → silent truncation of multi-byte device names (no overflow). Use `CFStringGetMaximumSizeForEncoding`. |
| 10 | LOW | cpp20-idiom | `M_PI` (POSIX macro) at `LufsMeter.h:425,445` while the rest uses `std::numbers::pi`; `(ptr,len)` pairs where `std::span` fits (`SpscRing`, `LufsMeter`, `MultichannelView::channel`); `std::memcpy` pun where `std::bit_cast` is cleaner (`PureModeFormat.cpp:163`); missing `[[nodiscard]]` on `computeBiquadCascade`. |
| 11 | LOW | consistency | `static constexpr` vs `inline constexpr` vs `constexpr` for namespace constants; trailing-vs-leading return type mixed *within* single classes; unnamed-namespace vs `static` for TU-local helpers. |
| 12 | NIT | slicing | `PureModeSource` polymorphic base exposes public defaulted copy/move (make `protected`). |
| 13 | NIT | misc | NOLINT reason on `AUParameterID` says `uint8_t` but the enum is `uint64_t` (copy-paste); `ParameterRamp::alpha` comment is backwards vs the code; `_pad` leading-underscore vs the tree's trailing-underscore members; multi-declarator POD structs; global `using namespace` in `AUAudioUnit.mm`. |

---

## The headline (finding 1)

```cpp
// TargetState.h:12  — sizes EQParams::biquads
static constexpr int kMaxBiquads = 10;
// EQModuleCoefficients.h:37 — bounds the fit + the copy-into-EQParams loop
static constexpr int kMaxBiquads = 10;
```
Two sources of truth for the same invariant, tied only by both happening to be `10`. `computeBiquadCascade`'s `result.biquads[i] = biquads[i]` loop is bounded by the *class* constant while `EQParams::biquads` is sized by the *namespace* constant — bump the class copy to fit more sections and you get a **silent out-of-bounds write on the struct that is then published to the RT thread**. Cheap, decisive fix: delete the class-scope copy, reference `AdaptiveSound::kMaxBiquads`, and `static_assert` the array extent against it.

---

## Cross-checks
- **Fool #1 (dlopen FFmpeg fragility)** — the ownership SME **verified the FFmpeg resolve/free paths are leak-clean and non-null on used paths**, so it's memory-safe as implemented. The ABI-robustness question remains an architectural note, not a defect.
- **Fool #2 (pragma-once comment false)** = finding 5, confirmed and *expanded* (a third inconsistency: the "collision-prone" bare guards are still everywhere).
- **Fool #4 (.mm pure C++)** = finding 6, confirmed with the project's own `.cpp` precedent.
- **Cross-stage thread:** Stage-1's fool flagged that `RtSwappableResource`'s leak-freedom leans on Realizer coalescing — and finding 3 shows the coalescing's *own* slots are racy. The Realizer control plane is the recurring soft spot.

---

## Proposed fix scope (pending founder go-ahead)

**Fix now** (clear, low-risk, high-value): **1** (kMaxBiquads unify + static_assert), **4** (uniform
C-ABI `noexcept` + hoist macro), **3** (Realizer slot mutex), **2** (delete dead CoreAudioDevice
listener), plus the cheap *misleading* items: **9** (cfString sizing), the false DSPKernel.h comment
from **5**, and the wrong NOLINT text + backwards `ParameterRamp` comment from **13**.

**Defer** (mechanical/build-touching — own commits): **5** full header-guard standardization
(~35 files), **6** `.mm`→`.cpp` migration (touches the build; verify per file), and the **7/8/10/11/12**
idiom-consistency batch.

**Decision needed:** finding 8 — document the `noexcept` terminate-on-thread-exhaustion stance
(recommended, matches the "unrecoverable" framing) vs drop `noexcept` and surface failure.

**Gate for any fix:** C++ null-test 120/120 + golden-master hash unchanged + `swift build` +
clang-format, same as Stage 1.

---

## Fix pass — outcomes (post-review, "fix all")

Gate: **null-test 120/120**, `GoldenMaster_StereoN2_v1` hash **unchanged** (`0xe7267654ba01d315`),
`swift build` clean, clang-format clean across the tree.

**Fixed:**
- **1 (HIGH, kMaxBiquads)** — removed the duplicate class-scope constant; the fitter now bounds
  itself by the single `AdaptiveSound::kMaxBiquads` that sizes `EQParams::biquads`.
- **2 (dead CoreAudioDevice listener)** — deleted the unused, defective, racy API (zero callers).
- **3 (Realizer slot race)** — added `slotMutex_`; the three `setPending*` writers and `drain()`'s
  read-and-clear now hold it (released before the cascade recompute/publish).
- **4 (C-ABI `noexcept`)** — hoisted the macro to `include/CApiNoexcept.h`; applied
  `AUDIODSP_C_NOEXCEPT` uniformly across all bridge decls **and** matching defs. *(Contract/uniformity
  value: the target is built `-fno-exceptions`, so the UB this guards is already precluded — noted.)*
- **5 (header guards)** — all 21 bare-`#ifndef` headers → `#pragma once`; corrected the false
  DSPKernel.h "plurality" comment.
- **6 (`.mm`→`.cpp`)** — renamed the 7 pure-C++ TUs (`DSPKernel`, `EQModule`, `LoudnessModule`,
  `CrossfeedModule`, `SpatialRenderKernel`, `ChannelLayoutDecoder`, `EQTestBridge`); updated the
  null-test script + `AudioDSPTestBridge` sources; they now compile as C++ and are clang-format-enforced.
- **7 (member order), 9 (cfString sizing), 11 (return-type consistency), 13 (misc)** — done:
  PureModeSession reorder, `CFStringGetMaximumSizeForEncoding`, within-class return-type unification
  (SpatialRenderKernel/LoudnessModule), `nodiscard`, `_pad`→`pad_`, declarator splits, `M_PI`→
  `std::numbers::pi`, `std::bit_cast`, `inline constexpr`, corrected NOLINT/ParameterRamp comments.
- **8 (OWN-4/5)** — documented the `startDecodeThread` `noexcept`/terminate stance; made
  `PureModeSource`'s copy/move `protected` (anti-slicing).

**Assessed and consciously NOT applied (net-negative — flagged, not silently dropped):**
- **IDM-8 (span-ify `MultichannelView::channel` / `SpscRing`)** — LOW idiom, but ripples `std::span`
  through **RT-hot, golden-master-sensitive** call sites (every module's `process()`). Churning the
  hot path for an idiom point is the wrong risk/reward; hold for a deliberate, separately-gated change.
- **IDM-15 (global `using namespace` in `AUAudioUnit.mm`/`SpatialRendererAU.mm`)** — NIT on working
  Obj-C++ bridge files that already qualify `AdaptiveSound::` in most places; removal is churn for
  negligible benefit.
- **IDM-7 / LimiterModule.h** — genuine 6-trailing/6-leading tie, no dominant style → left as-is.
- **IDM-10** — no file mixes file-scope `static` with an anonymous namespace → nothing to unify.

Deferred to when BRIR lands (unchanged from the review): the `RtSwappableResource` encapsulation.
