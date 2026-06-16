# Multichannel Pipeline — Epic Master Plan & Sprint Breakdown

**Document ID:** MULTICHANNEL-EPIC-001
**Date:** 2026-06-16
**Authors:** 4-expert collaboration — refactoring-specialist (lead) · audio-dsp-agent · modern-cplus-plus-expert · swiftui-pro
**Status:** Plan complete; ready to execute pending founder approval
**Companion:** [05-sprint-5b-multichannel-pipeline-plan.md](05-sprint-5b-multichannel-pipeline-plan.md) (architecture rationale + research citations)

---

## Mandate

Make AdaptiveSound **process AND render N channels** (mono..7.1, ceiling **8**) with **no naive
downmix**; spatial-render at the device boundary (binaural via BRIR when the device has fewer
channels than the source). **Data-parallel** algorithms. Code must be **safe, architecturally
correct, and elegant.**

## What this supersedes

The **sprint objectives** are reorganized around this epic. **Already-shipped code is retained as
the stereo foundation the epic generalizes — NOT reverted:**
- **Sprint 5a (done):** custom AU live in the graph (M1), 31-band EQ audible via the TargetState
  bridge (M2), Monitoring tab nav + N-channel-ready analyzer plumbing (M3 WIP).
- The old "Sprint 5 EQ-foundation" / "Sprint 6 clarity" objective framing is folded into this epic.
- The Monitoring-tab UI finish ([05-sprint-5-monitoring-tab-design.md](05-sprint-5-monitoring-tab-design.md))
  rides on top of the N-channel plumbing this epic lands.

---

## Safety net (the non-negotiable fence)

**Stereo must stay bit-exact at every sprint boundary.** Established BEFORE any production change:

- **Golden master (T-C1):** capture the current stereo DSP output for a fixed-seed chirp through a
  known non-trivial EQ + active limiter, as in-harness `constexpr` reference arrays. Every step
  re-runs and asserts `memcmp` bit-exact at N=2. The gate is `bash scripts/build-null-test.sh`.
- **Bridge/independence/linked/reconfig tests (T-C2..T-C5):** N=2-through-the-new-signature;
  per-channel independence at N=4/6/8 (distinct per-channel tones `f0·(k+1)` to catch crosstalk/
  reorder); linked-gain lockstep; stereo→5.1→stereo reconfiguration continuity. Written as failing
  stubs up front, filled in their target sprint.
- The existing C++ harness (19/19) + `VerifyAUGraph` offline-render pattern are the substrate
  (`swift test` is broken here).

---

## Elegant architecture (the "correct & elegant code" deliverable)

The naive migration would smear `std::array<…,8>` + `min(mNumberBuffers, kMaxChannels)` + per-channel
loops across every module (primitive obsession + shotgun surgery). Instead, **three value types
localize all channel knowledge:**

1. **`MultichannelView`** (`include/MultichannelView.h`) — a non-owning, RT-safe, planar (SoA) view
   over the ABL. `MultichannelView::fromABL(abl, frames)` is the **single place** `mNumberBuffers` is
   read and clamped to `kMaxChannels`; modules never touch `AudioBufferList` again. Pass by value
   (trivially copyable). A `const` sibling models the non-in-place renderer's read-only input — so a
   mistaken in-place assumption in the renderer is a *compile error*, not silent aliasing.
2. **`PerChannel<T>`** (`include/PerChannel.h`) — `std::array<T, kMaxChannels>` indexed by channel;
   fixed storage, zero RT heap. Replaces named `leftDelay_`/`rightDelay_`, `leftRing_`/`rightRing_`.
3. **`ChannelLayout`** (`include/ChannelLayout.h`) — decoded off-RT from the CoreAudio
   `AudioChannelLayoutTag` into `lufsWeights[]` (BS.1770: L/R/C=1, surround≈1.41, **LFE=0**),
   `brirAzimuth/elevation[]` (ITU-R BS.775), `isLfe[]`. Published via its **own**
   `DoubleBufferSnapshot` — deliberately **NOT** folded into `TargetState` (keeps the "EQ slider
   mutates only `.eq`" invariant; layout changes are rare, EQ changes are frequent). The render
   thread reads precomputed arrays — **never inspects a layout tag** (defeats the AAC-vs-broadcast
   ordering trap by construction).

**Policy encoded in types:** shared-across-channels state is a single member (EQ `setup`; limiter
`grBuf_`/deque/ballistics = the **linked** gain); per-channel state is `PerChannel<T>`. A reviewer
sees "the limiter gain is linked" directly from the fact that `grBuf_` is not `PerChannel`.

**Two-AU topology:**
```
player → AdaptiveSoundAU (N→N in-place: EQ→Clarity→Loudness→Limiter; BRIR REMOVED)
       → SpatialRendererAU ('aspz', N→deviceCh, NOT in-place; owns BRIR + post-binaural 2-ch limiter)
       → mainMixerNode (no-op: input already == deviceCh) → output
```
A second AU (not an extension of the effect AU) because the topologies differ (N→N in-place vs
N→M non-in-place) and the lifecycles differ (effect reconfigures on **track** change; renderer on
**device** change). BRIR moves out of the mid-chain to become the terminal boundary renderer.

---

## Sprint breakdown

Five sprints (labelled S0–S4 within the epic; renumber to the global sequence as you prefer). Each
ships stereo working at its boundary. Owners in brackets.

### S0 — Safety net + structural foundation  (~7 sp)
**Objective:** Lock the golden-master fence and introduce `MultichannelView`/`PerChannel`/
`ChannelLayout` with **zero behavior change**.
- Capture T-C1 golden master; write T-C2..T-C5 as failing stubs. [dsp]
- Add `kMaxChannels=8`; the three header types; refactor module `process(...)` to take a
  `MultichannelView`; `fromABL` becomes the sole ABL-decode point. Module bodies stay N=2-identical. [c++]
- **Move the "after" monitoring tap from `mainMixerNode` → the AU output bus** (+ separate
  `afterTapInstalled` flag); introduce the `GraphState` enum (no behavior change). [swift]
- **Exit:** 19/19 + T-C1 + T-C2 pass; one and only one `mNumberBuffers` read in the codebase
  (grep-gated); stereo sounds identical; no RT alloc.

### S1 — C++ modules N-channel (stereo-driven)  (~8 sp)
**Objective:** EQ + Limiter + Loudness process N channels internally; graph still stereo (N=2 end-to-end).
- EQ: `PerChannel<delay>`, per-channel `vDSP_biquad` loop, **shared coeffs + click-free swap
  preserved verbatim** (do NOT pull `vDSP_biquadm` forward — it resets delays → clicks). [c++/dsp]
- Limiter: `PerChannel<ring>`; `polyphaseIspPeak` fan-in = **max ISP over all N** → ONE shared gain
  applied to all (linked). At N=2 this reduces to today's exact behavior. [c++/dsp]
- Loudness: makeup **gain applied to all N channels**. **Upgrade `LufsMeter` to N-channel BS.1770
  weights here** (or explicitly cap+label) — else makeup overshoots on surround (DSP gap #1). [dsp]
- Fill T-C3 (independence), T-C4 (linked lockstep), per-channel FR accuracy, click-free-at-N>2,
  N-channel hot-noise soak. [dsp]
- **Exit:** T-C1/T-C2 bit-exact; T-C3/T-C4 + new N-channel tests pass; clang-tidy clean; stereo unchanged.

### S2 — Source-driven N input + graph at N (interim mixer fold)  (~8 sp)
**Objective:** A 5.1/7.1 file is scheduled at native channel count, processed at N through the AU,
monitored at N. Mixer still folds to the device (documented interim). Stereo unaffected.
- Derive formats from `AVAudioFile.processingFormat` (carries layout); **explicit
  `AVAudioChannelLayout` for 5.1+**; pin graph 48 kHz. [swift]
- `reconfigureGraph(to:)` lifecycle: `player.stop` → remove taps → `engine.pause` (NOT stop) →
  rebuild formats → re-negotiate AU bus count → re-init kernel at N → rebuild analyzers → start →
  reinstall taps; fast-path skip when count unchanged; call **before** `scheduleFile`. [swift]
- AU bus count parameterized; kernel re-inits at negotiated N in `allocateRenderResources`. [c++]
- Decode `ChannelLayout` off-RT + publish; **layout-tag round-trip test** (MPEG_5_1_A / _B /
  MPEG_7_1 / a broadcast ordering) — hard gate before any BRIR (DSP gate D). [dsp]
- Finish the **Monitoring UI** (per-channel rows, `Canvas`-based `SpectrumMiniView`, tab-visibility
  gated poll) — now shows N rows. [swift]
- Keep limiter ceiling at **−6 dBTP during the interim** so the mixer fold can't clip. [dsp]
- **Exit:** T-C5 passes; stereo A/B unchanged; 5.1 file shows 6 monitor rows + plays (folded);
  reconfiguration stereo→5.1→stereo clean; layout decode verified.

### S3 — SpatialRendererAU passthrough/route  (~8 sp)
**Objective:** New `'aspz'` AU; device ≥ N → bit-exact passthrough/route; mixer becomes a no-op.
- `SpatialRendererAU` + `SpatialRenderKernel` (non-in-place, `_inputScratch` preallocated); identity
  channel-map route via vDSP. C-ABI `createSpatialRendererAU` / `configureChannels`. [c++]
- Wire `player→AU→SpatialRenderer→mixer`; `AVAudioEngineConfigurationChange` handler re-negotiates on
  device change (effect AU NOT re-instantiated). [swift]
- **Zero-XRun soak** at N=6/8 on the M1 Pro floor (DSP gap #4); passthrough bit-exact test. [dsp]
- **Exit:** stereo-on-stereo bit-exact through the full graph; device hot-plug reconfigures; no XRuns.

### S4 — BRIR binaural path + post-binaural limiter  (~10 sp) — headline DSP
**Objective:** device < N → per-channel HRIR convolution N→2 at BS.775 positions, summed binaural,
then a 2-ch post-binaural −1 dBTP limiter.
- BRIR per-channel convolution (vDSP / partitioned), shared late-reverb tail (**split-point spec
  decided up front** — DSP gap #3), 2-slot click-free hot-swap via `BRIRParams.activeSlotIndex`,
  LFE excluded. [c++/dsp]
- **Pre-binaural limiter ceiling MEASURED on the actual SADIE II HRIRs** (not the +9 dB estimate),
  committed to `AudioConstants.h`; post-binaural enforces −1 dBTP (DSP gate B). [dsp]
- Verify: finite/non-silent/energy-preserving (±3 dB), ITD/ILD sanity, hot-swap no-click,
  **libebur128 multichannel oracle** for BS.1770 weights (±0.2 LU). [dsp]
- **Exit:** stereo stays on passthrough (no regression); 5.1→headphones binaural audible; true-peak
  ≤ −1 dBTP under all stimuli; soak clean.

---

## Verification matrix (per step)

| Test | S0 | S1 | S2 | S3 | S4 |
|---|---|---|---|---|---|
| Golden N=2 bit-exact (T-C1/T-C2) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Per-channel independence (distinct tones) | stub | ✅ | ✅ | ✅ | ✅ |
| Limiter linked-gain lockstep | stub | ✅ | ✅ | ✅ | ✅ |
| Reconfiguration continuity (T-C5) | stub | — | ✅ | ✅ | ✅ |
| Click-free EQ swap at N>2 | — | ✅ | ✅ | ✅ | ✅ |
| Channel-layout tag round-trip | — | — | ✅ | ✅ | ✅ |
| Zero-XRun soak N=6/8 | — | — | — | ✅ | ✅ |
| BRIR finite/energy/ITD-ILD + libebur128 oracle | — | — | — | — | ✅ |
| True-peak ≤ −1 dBTP (two-limiter) | ✅ | ✅ | ✅ | ✅ | ✅ |

**Gates that must not slip:** (A) click-free EQ swap survives S1; (B) −1 dBTP through the two-limiter
topology — pre-binaural ceiling measured, not guessed; (C) BS.1770 multichannel weights never
silently degrade to stereo-fold (makeup-gain overshoot); (D) layout decode proven before BRIR; (E)
zero RT allocation (ASAN + allocator hook).

---

## Risks (ranked)

1. **Count-only `AVAudioFormat` at 5.1+** (silent channel mis-order) → always pass explicit
   `AVAudioChannelLayout`; debug `assert(layout != nil || channels ≤ 2)` at every connect.
2. **Hidden input downmix at `scheduleFile`** → derive player format from `processingFormat`;
   reconfigure **before** scheduling.
3. **Reconfiguring a running engine** → `pause` (not `stop`); remove taps first; `GraphState` guards re-entry.
4. **Tap channel-count drift** → relocate "after" tap to AU output in S0 (before it can bite).
5. **RT allocation when kMaxChannels grows** → fixed `PerChannel`/scratch sized off-RT; ASAN gate.
6. **Linked vs independent limiting** → linked is mandated; quality bug if wrong (image shift).
7. **`vDSP_biquadm` click temptation** → keep per-channel `vDSP_biquad` loop; biquadm is a later, measured swap.
8. **BRIR is the largest single piece** → isolated in S4 behind the renderer; S0–S3 ship a working
   pipeline (channel-truncation at the boundary) without it.

---

## File map

- New: `include/MultichannelView.h`, `include/PerChannel.h`, `include/ChannelLayout.h`,
  `Spatial/SpatialRenderKernel.{h,mm}`, `AudioEngine/SpatialRendererAU.mm`.
- Changed: `include/AudioConstants.h` (`kMaxChannels`), `DSPKernel.{h,mm}`, `EQ/EQModule.{h,mm}`,
  `Limiting/LimiterModule.h`, `Loudness/{LufsMeter.h,LoudnessModule.*}`, `include/AudioUnitBridge.h`
  + the pure-C bridge, `AudioEngine/AUAudioUnit.mm`, `AudioEngineBridge.swift`, `AudioViewModel.swift`,
  `UI/Tabs/MonitoringTabView.swift`, `Tests/DSPKernelNullTest.cpp` (+ `VerifyMultichannelGraph` /
  `VerifyDeviceBoundary` harness targets).

---

## Sequencing

`S0 → S1 → S2 → S3 → S4` is a strict dependency chain (each consumes the prior). Parallelism: within
S0 (C++ types ∥ Swift tap move), within S1 (EQ ∥ Limiter), and S4 HRIR-data prep can begin during S3
review. Everything up to S3 is shippable as a working multichannel pipeline; S4 is the quality ceiling.
