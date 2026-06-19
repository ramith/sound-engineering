# Multichannel Pipeline — Architecture & Implementation Plan

> **✅ SHIPPED — historical record (Sprint 5b, shipped & merged).** This is the as-built/as-planned record, retained for provenance and design detail. The authoritative forward sprint schedule is now [sprint-plan.md](sprint-plan.md).

**Document ID:** MULTICHANNEL-PIPELINE-001
**Date:** 2026-06-16
**Author:** Synthesized from a 3-discipline panel review (audio-DSP + research · modern-C++ · Swift)
**Status:** Architecture approved-in-principle (founder mandate); implementation plan ready
**Scope:** A dedicated epic — make AdaptiveSound process **and** render **N channels** (mono..7.1,
ceiling 8) with **no naive downmix**; spatial-render to the device at the boundary.

---

## Mandate (founder, 2026-06-16)

1. The DSP **algorithms must process and render N channels correctly** — no downmixing in the chain.
2. **Output boundary:** when the device has fewer channels than the source (e.g. 7.1 → stereo
   headphones), **spatial-render** (binaural via the BRIR module), never a lossy sum. When the
   device has ≥ N channels, pass through / route.
3. **Data-parallel** the algorithms (see §5 — explicit deliverable).
4. Practical ceiling: **7.1 (8 channels)**.

---

## Current state — stereo is locked in FOUR layers

Fixing one layer alone produces silent/corrupt output; all four must move together.

1. **Swift graph** — `AVAudioFormat(…channels: 2)` forces every connection + input file to stereo
   (`AudioEngineBridge.swift`). This is the input-side downmix.
2. **AU bus arrays** — `kStereoChannelCount = 2`; both buses built stereo (`AUAudioUnit.mm`).
3. **DSP modules** — `EQModule` (`leftDelay_`/`rightDelay_`, clamps to 2), `LimiterModule`
   (`kLimiterMaxChannels = 2`, `leftRing_`/`rightRing_`), `LoudnessModule` (stereo fold).
4. **`mainMixerNode`** — AVAudioEngine silently downmixes to the device channel count at the mixer.
   *This* is the output-side downmix to intercept.

Good news: the **kernel orchestration is already channel-agnostic by signature** (`process(AudioBufferList*, frames)` could iterate `mNumberBuffers`); the AU's **non-interleaved ABL is already planar/SoA** (no deinterleave needed); `BRIRModule`/`ClarityModule` are stubs (binaural is built fresh, not retrofitted); `BRIRParams.activeSlotIndex` already exists for convolver hot-swap.

---

## Target graph

```
AVAudioPlayerNode  (player out = 48 kHz, N ch, source's channel layout)
   │  N-ch
   ▼
AdaptiveSoundAU  [aufx, in-place, N-in/N-out]   EQ → Clarity → Loudness → Limiter   (BRIR removed from here)
   │  N-ch                                       per-channel state; LINKED limiter gain
   ▼
SpatialRendererAU  [new, 'aspz', NOT in-place, N-in / deviceCh-out]
   │     device ≥ N  →  channel-map passthrough / route (vDSP, identity matrix)
   │     device  < N  →  BRIR binaural render (N → 2) + post-binaural 2-ch true-peak limiter
   │  deviceCh
   ▼
mainMixerNode  →  outputNode → device      (mixer is now a NO-OP: input already == deviceCh)
```

**Why a separate `SpatialRendererAU` (not an extension of the effect AU):** different bus topology
(N-in/N-out in-place vs N-in/M-out non-in-place — an in-place AU cannot change channel count),
different lifecycle (effect reconfigures on **track** change; renderer on **device** change), and
the BRIR convolver state belongs at the boundary. **BRIR moves out of the mid-chain** — binauralization
is fundamentally a terminal N→2 *output* op, which a mid-chain in-place module can't do.

**Two limiter passes:** the main N-channel limiter protects the pre-spatial signal; a small
post-binaural 2-channel limiter catches the inter-sample peaks the HRTF convolution creates (the
N→2 incoherent sum can be up to ~+9 dB, so the pre-binaural limiter targets extra headroom, e.g.
−6 dBTP, and the post stage enforces the final −1 dBTP). This matches Dolby Atmos binaural practice.

---

## Per-module changes

| Module | Change | Note |
|---|---|---|
| **EQ** | Per-channel delay state `std::array<std::array<float,…>, kMaxChannels>`; **coefficients shared** across channels; loop `vDSP_biquad` per channel (keep the click-free swap). `vDSP_biquadm` = measured optimization later. | Identical tonal curve on every channel is correct. |
| **Limiter** | **LINKED gain**: max true-peak (ISP) across ALL channels → ONE gain envelope → applied to every channel. Per-channel rings, shared `grBuf_`/deque/ballistics. | Preserves imaging (per-channel GR shifts phantom sources > JND). Already today's topology — just generalize the fan-in. LFE detection policy = TODO. |
| **Loudness** | BS.1770-5 **multichannel weights** (L/R/C = 1.0; surround = +1.5 dB / ×1.41; **LFE excluded**); makeup **gain applied to all N channels**. | Measurement weighting may stay stereo-fold short-term (it's off the RT path / Swift tap); gain application must be N-channel now. |
| **BRIR** (boundary) | Per-channel HRIR convolution at fixed ITU-R BS.775 speaker positions (L −30°, R +30°, C 0°, Ls −110°, Rs +110°, 7.1 sides ±90°, backs ±135°) → summed to binaural L/R; shared late-reverb tail across channels. | The standard virtual-surround model (Apple Spatial Audio / Dolby / Steam Audio). Per-channel BRIR preferred over ambisonics (lower blur/latency). |
| **Clarity** (stub) | When built: linked sidechain like the limiter. | — |

**Channel layout:** decode the CoreAudio `AudioChannelLayoutTag` at format negotiation (off-RT) into
a `ChannelLayout { numChannels; lufsWeights[]; brirAzimuth[]; brirElevation[] }`; publish via the
existing lock-free snapshot. The render thread reads only the precomputed arrays — never inspects
tags. **Never hardcode slot→role** (the AAC `MPEG_5_1_A` = L R C LFE Ls Rs vs broadcast orderings
trap silently corrupts BS.1770 weighting + BRIR positions).

---

## §5 Data-parallel architecture (explicit deliverable)

**Core principle: vectorize across *frames* (the long, contiguous dimension — vDSP/NEON), loop
across *channels* (short, ≤ 8).** This matches both the data (planar, frames contiguous) and the
hardware (Accelerate eats contiguous float runs).

- **Layout — planar SoA, channel-major, preallocated for `kMaxChannels = 8`.** The AU delivers a
  non-interleaved ABL (one contiguous buffer per channel) — **already the ideal layout; no
  deinterleave/reinterleave step.** Matches JUCE `AudioBuffer` and every Accelerate `const float* const*`
  API. All per-channel state is `std::array<State, kMaxChannels>` (fixed; zero RT heap; ~71 KB total
  working set at 8 ch — fits L1 on Apple Silicon).
- **EQ — `vDSP_biquadm`** filters all N channels in ONE SIMD call (vs N `vDSP_biquad`). Caveat: a
  new `vDSP_biquadm` setup resets internal delays → a click on each EQ change; so either (a) keep the
  per-channel `vDSP_biquad` loop with external delay arrays for the first cut (preserves the
  hard-won click-free swap; the loop is not the bottleneck at ≤8 ch), or (b) adopt
  `vDSP_biquadm_SetTargetsDouble` for in-place, ramped coefficient updates (the right long-term
  answer, subsumes the master-gain ramp). **Recommendation: (a) now, (b) as a measured follow-up.**
- **Limiter — SIMD / `vDSP_dotpr`** for the per-sample 8-phase × 24-tap ISP FIR (per channel; ~2.5%
  of one core at 8 ch). The gain is **shared**, so nothing to vectorize across channels there;
  apply via per-channel `vDSP_vmul` of the shared `grBuf_`.
- **Loudness** — per-channel K-weight biquads (double precision; no vDSP double multichannel) in a
  simple loop; negligible, and off the RT render thread anyway.
- **Threads vs SIMD:** prefer single-thread SIMD/vDSP for the bus chain (short, L1-resident — Audio
  Workgroup threads would cost more than the work). Reserve Audio Workgroups for the future
  per-stem object engine (genuinely independent, compute-heavy BRIR convolutions).
- **Alignment/clang-tidy:** prefer Accelerate (`vDSP_dotpr`/`vDSP_vmul`) over hand-SIMD (alignment-safe,
  lint-clean); stack pointer-gather arrays as `std::array<float*, kMaxChannels>`; no `std::vector`
  resize on RT; `-fno-exceptions` (null-check `vDSP_biquadm_CreateSetup`).

---

## Migration plan (incremental; stereo stays bit-exact at every step)

The fence: at `numChannels == 2` with identity params, `DSPKernelNullTest.cpp` must stay bit-exact.
Capture a **golden N=2 reference** as the strongest "didn't change stereo" guard.

- **Step 0 — Plumbing (no behavior change).** `kMaxChannels = 8` in `AudioConstants.h`; add
  defaulted `maxChannels`/`numChannels` to `initialize`/`process`; centralize `activeChannels =
  min(mNumberBuffers, kMaxChannels)` in `DSPKernel::process`. **Move the M3 "after" monitoring tap
  from `mainMixerNode` to the AU output** (so "after DSP" = N-channel post-limiter, not the
  device-folded mixer). Ship; stereo identical.
- **Step 1 — C++ modules N-channel, driven at N=2.** EQ per-channel delay; limiter linked-GR over
  N; loudness N-channel gain. Gate on the null-test (bit-exact at N=2) + new N-channel harness tests
  (distinct per-channel signals to catch crosstalk/reorder; linked-gain test; FR-per-channel).
- **Step 2 — Source-driven N input + AU at N** (temporarily let the mixer downmix to device). A 5.1
  file is now *processed* at 5.1 through the AU; monitoring shows 6 channels. Output still stereo via
  the mixer fold (interim). De-risks input/AU/reconfig independently.
- **Step 3 — `SpatialRendererAU` passthrough/route** (no BRIR yet). Multichannel device gets true
  N-channel output, mixer becomes a no-op. Verify on a 6/8-ch interface.
- **Step 4 — BRIR binaural path** (N→2 + 2-slot convolver hot-swap + post-binaural limiter). Headphones
  now get spatialized surround instead of a fold. Largest DSP piece; lands last.

**Engine lifecycle:** reconfigure the graph on track channel-count change (fast-path skip when
unchanged): `player.stop()` → remove taps → `engine.pause()` (not stop — keeps the device open) →
rebuild N-channel `graphFormat` **with an explicit `AVAudioChannelLayout`** (count-only formats
misbehave at 5.1+) → re-negotiate AU + renderer bus counts → reconnect → re-init kernel at N →
rebuild monitoring analyzers → `engine.start()` → reinstall taps. **Do not re-instantiate the AU**
(keep the kernel-lives-with-the-AU ownership). Pin the graph to 48 kHz (player converts file rate,
preserves channels) so every DSP coefficient design stays on one rate.

---

## Testing

- Extend the offline-render harness pattern (`VerifyAUGraph`) → `VerifyMultichannelGraph` +
  `VerifyDeviceBoundary` (runnable via `swift run`; `swift test` is unusable here).
- **Distinct per-channel signals** (channel k = sine at `f0·(k+1)`) so channel swap/collapse/crosstalk
  is detectable (a single tone on all channels can't catch it).
- N-channel identity passthrough (N = 1, 4, 6, 8) bit-exact; per-channel independence (no delay
  bleed); **limiter linked-gain** (hot signal on ch0 ducks ALL channels in lockstep); FR-per-channel.
- Reconfiguration test (render stereo → reconfigure to 5.1 → render 5.1 in one engine instance).
- Device-boundary: deviceCh = N → passthrough bit-exact; deviceCh = 2 → binaural finite/non-silent/
  energy-preserving; null-test asserts ~0 dB delta when DSP bypassed.

---

## Risks (ranked)

1. **Hidden input downmix at `scheduleFile`** — always derive the player format from
   `AVAudioFile.processingFormat` (carries the layout); a count-only format folds/mis-maps.
2. **Count-only `AVAudioFormat` at 5.1+** — pass an explicit `AVAudioChannelLayout` or connect throws/
   mis-orders. The most common AVFoundation multichannel mistake.
3. **Reconfiguring a running engine** — pause→reconnect→reallocate→start discipline is mandatory.
4. **Tap channel-count drift** — the mixer's channel count *changes meaning* (→ deviceCh); N-channel
   monitoring taps must live on the AU output, not the mixer (Step 0).
5. **RT-path per-channel allocation** — size all per-channel state in `initialize()` (off-RT) to
   `kMaxChannels`, index by active N at render.
6. **Linked vs independent limiting** — independent per-channel GR is a quality regression (image
   shift), not a crash. Linked-max is the correct, mandated choice.
7. **BS.1770 multichannel semantics** — don't pass a stereo-fold meter off as true multichannel ITU
   loudness; document, and weight properly (LFE excluded) when it goes N-channel.

---

## Effort / sequencing

This is a **multi-milestone epic**, larger than a single sprint, and is **independent of the M3
Monitoring UI** (which is N-channel-ready and shows N rows automatically once this lands). Suggested
order: Step 0 (plumbing + tap move) → Step 1 (C++ N-channel + tests) → Step 2 (source-driven input)
→ Step 3 (spatial passthrough) → Step 4 (BRIR binaural). Steps 0–1 are provable bit-exact before any
audible change; the binaural renderer (Step 4) is the headline DSP deliverable.

Recommended cadence: finish the **M3 Monitoring UI** first (small, N-ready, gives an immediate visual
win + a tool to *watch* the multichannel work), then run this epic Step 0 → 4 with the panel's
experts re-engaged per step.

---

## Research / citations (from the DSP review)

- ITU-R BS.1770-5 (multichannel loudness, channel weights, LFE exclusion); ITU-R BS.775-4 (speaker
  positions). Apple Accelerate `vDSP_biquadm` + `vDSP_biquadm_SetTargetsDouble` (multichannel biquad).
  Apple Audio Workgroups (parallel RT threads). CoreAudio `AudioChannelLayout` / QA1638 (channel order).
  FabFilter Pro-L 2 (channel-linked true-peak limiting). Valve Steam Audio / Audiomovers Apple Music
  binaural (per-channel BRIR virtual surround). JUCE `AudioBuffer` (planar channel-major). AES 2017
  binaural/surround rendering survey; Binamix (arXiv 2505.01369). Full URLs in the panel transcript.
