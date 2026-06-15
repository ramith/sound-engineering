# Prior-Art & Reuse Research — Adaptive Sound

**Status:** Draft v0.1 · **Date:** 2026-06-12 · **Method:** 5 parallel web-research passes, licenses verified against authoritative sources.

This is the output of the architecture process's **Prior-Art & Reuse gate**: before we build any component, we check what macOS already provides and what permissively-licensed prior art exists, so we don't reinvent solved problems and don't accidentally take on incompatible code.

## License policy (gating rule — LD-9)

The project is open-source with the license **deferred to post-MVP but required to be redistributable**. Therefore:

- ✅ **Shippable** = permissive: MIT, BSD-2/3, Apache-2.0, Boost, 0BSD, ISC, zlib, public-domain.
- 🚫 **Reference-only** = copyleft or non-redistributable: GPL/AGPL/LGPL, CC-BY-NC / NC-SA / NC-ND, "research-only", or unverified. We may **study** these and **reimplement** the idea cleanly, but **not copy code or ship their weights/data**.
- ⚠️ **Verify** = a license claim we could not pin to authoritative text — confirm before relying.

> **Code license ≠ weights/data license.** Several ML projects are MIT-code but NC-licensed weights. Always check both.

---

## 1. Headline findings that change the architecture

Three results are significant enough to shape the design:

1. **Phase 2 may not need a driver at all.** macOS 14.2/14.4+ **Core Audio process taps** support a *muted global tap + private aggregate device* topology: capture all system audio, mute the original, run our C++ kernel, and play the processed result to the real device — **with no HAL plug-in to sign/notarize/install and no privileged helper.** Recommendation: make **process taps the primary Phase-2 mechanism**, with the AudioServerPlugIn virtual device (via **libASPL**, MIT) as the fallback for older macOS. (Sample: `AudioCap`, BSD-2.) Confirm exact tap symbols + min-OS in the SDK headers.

2. **Custom binaural must be built, not borrowed.** Apple's PHASE / `AVAudioEnvironmentNode` (HRTF/HRTFHQ) / AUSpatialMixer all apply **fixed, non-replaceable** Apple HRTFs — no API to load a SOFA dataset, no access to the user's personalized HRTF. For dataset-driven, quality-first spatialization we must do our **own SOFA-HRIR partitioned convolution** (loader: **libmysofa**, BSD-3; convolution: vDSP / **FFTConvolver**, MIT), driven by **`CMHeadphoneMotionManager`** for head tracking (which *is* available on macOS 14+).

3. **Real-time ML uses BNNS Graph, not Core ML.** For any ML on the audio thread, **BNNS Graph** is the RT-safe path (no runtime allocation, single-threaded, no locks — built for this). **Core ML / Metal are off-RT only** (dispatch latency, allocation) — fine for non-RT pre-analysis, never inside the render block.

---

## 2. Reuse-vs-build by component

Legend: **Use-native** (Apple framework) · **Reuse** (ship permissive OSS) · **Build** (write our own, optionally from a reference) · **Ref-only** (study, don't copy).

### Engine & integration
| Need | Decision | Pick | License |
|---|---|---|---|
| Playback + DSP host | Use-native | AVAudioEngine + custom `AUAudioUnit` v3 (decided) | Apple SDK |
| AUv3 + C++ kernel reference | Ref → Reuse | **bradhowes/LPF** (actively maintained, clean) | MIT |
| AU hosting SDK | Reuse | Apple **AudioUnitSDK** | Apache-2.0 |
| Swift ↔ C++ | Use-native | Swift/C++ interop + C++ facade (render thread stays pure C++) | toolchain |
| Multicore RT scheduling | Use-native | **Audio Workgroups** (`os_workgroup`) — join aux RT threads once, off hot path | Apple SDK |

### EQ
| Need | Decision | Pick | License |
|---|---|---|---|
| Minimum-phase parametric EQ | Use-native + Build | `vDSP.Biquad`/`vDSP_biquadm`, coeffs from **RBJ Audio EQ Cookbook** | Apple SDK + public-domain math |
| **Linear-phase FIR EQ** (latency is free) | Reuse / Build | **FFTConvolver** (partitioned conv.) backed by vDSP FFT; **SmoothIR** as design ref ("bake EQ curve → 1 IR + hybrid head/tail") | MIT / BSD-3 |
| Higher-order filter design | Reuse | **DSPFilters** (Butterworth/Cheby/Elliptic/Bessel), **cycfi/q** | MIT / Boost |
| (avoid for code) | Ref-only | JUCE `juce_dsp`, **KFR** | AGPL / GPL |

### Dynamics & enhancement
| Need | Decision | Pick | License | Notes |
|---|---|---|---|---|
| Look-ahead limiter | Reuse + Build | **dariosanfilippo/LimiterClass** core + our vDSP oversampling for **true-peak** (ITU-R BS.1770) | MIT | LimiterClass is sample-peak only; add ISP oversampling |
| Compressor / multiband | Reuse + Build | **Chunkware SimpleSource** or **sndfilter** primitives; multiband via Linkwitz-Riley crossovers | MIT / 0BSD | Modern adaptive algo (CTAGDRC) is GPL → ref-only |
| Crossfeed | Reuse / Build | **libbs2b** (Bauer) ⚠️ *license disputed — see §5*; algorithm is public, trivial to reimplement on biquads | MIT? / GPL? | `lalkaboss/BS2B-crossfeed-macos` = AU-hosting ref |
| **Psychoacoustic bass** | **Build** ⚠️ patent | NLD from **mono-summed** low band (ATSR/tanh per DTVBE; eloimoliner DAFx-20 ref) | papers | **See §6 patent watch — do NOT do per-channel/stereo bass** |
| Exciter / "air" | Reuse / Build | **jatinchowdhury18/Aphex_Exciter** core (decouple from JUCE) + oversample | BSD-3 | |

### Spatial
| Need | Decision | Pick | License |
|---|---|---|---|
| Binaural HRTF | **Build** | Own SOFA-HRIR partitioned convolution (Apple HRTF not swappable) | — |
| SOFA loader | Reuse | **libmysofa** (k-d tree lookup + resampler) | BSD-3 |
| Convolution engine | Use-native / Reuse | vDSP partitioned convolution, or **FFTConvolver** | Apple SDK / MIT |
| Head tracking | Use-native | **CMHeadphoneMotionManager** (macOS 14+) → feed our renderer | Apple SDK |
| HRTF dataset (default) | Reuse (ship) | **SADIE II** (SOFA-native, high quality) | **Apache-2.0** |
| HRTF datasets (also OK) | Reuse (ship) | MIT KEMAR (cite), **CIPIC** (commercial OK — common "NC" claim is *false*), ARI (CC BY-SA — keep data under SA) | mixed-permissive |
| Spatial fallback | Use-native / Ref | PHASE / `AVAudioEnvironmentNode` (fixed Apple HRTF) | Apple SDK |
| Room/reverb IRs | Reuse (per-file) / Build | OpenAIR / Freesound **CC0/CC-BY only**; or synthesize (image-source/FDN) | per-IR |

### Analysis, loudness & ML (non-RT pre-analysis)
| Need | Decision | Pick | License |
|---|---|---|---|
| Loudness / true-peak (LUFS, BS.1770) | Reuse | **libebur128** | MIT |
| Genre/mood (on-device) | Use-native | **Create ML**-trained model via **Core ML / SoundAnalysis** (train on redistributable data) | Apple SDK + our model |
| Content-type detector | Reuse | **YAMNet** (Apache-2.0 weights) → Core ML | Apache-2.0 |
| BPM / key / spectral features | Build | Reimplement on **vDSP**, using **librosa** (ISC) as the spec | ISC ref → our code |
| Headphone correction curves | Reuse | **AutoEq** computed parametric curves (+ attribution) | MIT (verify upstream measurement provenance) |
| Source separation (future, offline) | Reuse | **Demucs/HTDemucs** via **MLX port** (offline only — heavy) | MIT (code); weights NC-trained — auto-downloaded on first run, not redistributed |
| (avoid for code/weights) | Ref-only | **Essentia** (AGPL + NC-ND models), **aubio**, **libKeyFinder/QM-DSP** (GPL), Open-Unmix/MusicNN weights (NC) | copyleft/NC |

### Phase 2 — system-wide
| Need | Decision | Pick | License |
|---|---|---|---|
| **Primary** mechanism | Use-native | **Core Audio process taps** (muted global tap + private aggregate device) — no driver | Apple SDK; AudioCap sample BSD-2 |
| Fallback (older macOS) | Reuse | **libASPL** AudioServerPlugIn framework | MIT |
| Architecture blueprint | Ref-only | **eqMac** (closest analog; note shipping code is a closed fork) | Apache-2.0 (v1.3.2 snapshot) |
| Driver references | Ref-only | BlackHole, Background Music | GPL |
| Privileged install (if driver path) | Use-native | **SMAppService** (not deprecated SMJobBless) + Developer ID + notarization | Apple SDK |

---

## 3. Recommended native-first framework stack

Lean on these before writing or importing anything:

- **Accelerate / vDSP / vForce** — the RT DSP workhorse (biquads, FFT, convolution, vector math). RT-safe.
- **AudioToolbox stock Audio Units** — `AUNBandEQ`, `AUDynamicsProcessor`, `AUReverb`/`AUMatrixReverb`, AUSpatializer — Apple-tuned, RT-safe, zero build cost. Use for standard blocks; build custom only for a signature behavior.
- **BNNS Graph** — RT-safe ML inference *inside* the render thread (build graph off-thread, execute on RT).
- **Core ML / SoundAnalysis / Create ML** — off-RT analysis & training (genre/mood). Never on the render thread.
- **Metal / MPS** — heavy offline/parallel work only (no first-class FFT — prefer vDSP).
- **AVAudioConverter** — sample-rate conversion; use `…Quality_High` / `…Complexity_Mastering`. Pre-configure once (it can allocate on reconfig).
- **Audio Workgroups (`os_workgroup`)** — keep multi-threaded RT DSP deadline-safe.
- **CMHeadphoneMotionManager** (macOS 14+) — AirPods head tracking → our spatializer.
- **PHASE** (macOS 12+) — optional, if we ever want Apple-managed spatialization.

---

## 4. Clean-reuse shortlist (the "yes, ship it" set)

`bradhowes/LPF` (MIT) · Apple `AudioUnitSDK` (Apache-2.0) · `FFTConvolver` (MIT) · `DSPFilters` (MIT) · `cycfi/q` (Boost) · `LimiterClass` (MIT) · `Chunkware SimpleSource` (MIT) · `sndfilter` (0BSD) · `Aphex_Exciter` (BSD-3) · `libmysofa` (BSD-3) · **SADIE II** (Apache-2.0) / KEMAR / CIPIC HRTFs · `libebur128` (MIT) · `YAMNet` (Apache-2.0) · `AutoEq` curves (MIT) · `Demucs` code + MLX port (MIT), weights auto-downloaded (NC-trained) · `libASPL` (MIT) · `AudioCap` (BSD-2).

## 5. ⚠️ Open verifications (confirm before relying)

| Item | Issue | Action |
|---|---|---|
| **libbs2b license** | Agents disagree: one verified **MIT** from source headers; another reported **GPL-2.0+** | Open the repo `LICENSE`/source headers; if not clearly MIT, **reimplement** (algorithm is public — a few biquads + delay) |
| FFTConvolver `LICENSE` file | README says MIT, canonical `/LICENSE` path 404'd | Confirm filename in-repo before vendoring |
| Apple "Creating Custom Audio Effects" sample | Sample license likely bars verbatim redistribution | Adapt patterns, don't ship the file; read bundled LICENSE.txt |
| IRCAM Listen HRTF terms | Only informal "any use" notice; page wouldn't load | Verify before shipping; SADIE/CIPIC/KEMAR already cover us |
| Harman target curve | No explicit license found | Use AutoEq's bundled targets; avoid "Harman" trademark claims |
| AutoEq raw upstream measurements | Repo MIT, but measurers (oratory1990/Crinacle) may be CC-BY-NC-SA | Ship AutoEq's *computed* curves w/ attribution; don't republish raw DBs unchecked |
| MusicNN weights | Likely CC-BY-NC-SA | Verify repo LICENSE; prefer training our own |
| Core Audio tap symbols + min-OS | Exact `CATapDescription` initializers / `muteBehavior` + 14.2 vs 14.4 unconfirmed (JS-rendered docs) | Confirm in `<CoreAudio/AudioHardwareTapping.h>` headers |

## 6. 🛑 Patent watch — psychoacoustic bass

Virtual-bass is patent-dense. The *principle* (missing-fundamental perception) is unpatentable; specific implementations are not.

- **US 5,930,373 (Waves / MaxxBass, 1997)** — appears **EXPIRED (~2019)** → original nonlinear-multiplier + harmonics approach likely free. **Verify on USPTO before shipping.**
- **US 11,102,577 (Waves, stereo virtual bass, filed 2018)** — **ACTIVE to ~2038.** Covers *per-channel* harmonic generation that preserves stereo image. **Avoid** → generate bass harmonics from a **mono-summed (L+R) low band** (the classic approach this patent distinguishes itself from).
- **SRS/Xperi** — older patents likely expired (~2006–08, uncertain); several newer Xperi virtual-bass patents may be active → avoid those specific techniques.

**Action:** implement the mono-summed NLD design; **get formal IP review before any public release.** (Not legal advice.)

---

## 7. ADR stubs (to formalize as we lock each)

- **ADR-001 — Foundation:** AVAudioEngine host + single custom `AUAudioUnit` (C++ DSP kernel), Swift/C++ interop facade. *Status: Accepted.*
- **ADR-002 — Phase-2 mechanism:** Core Audio process taps (primary) + libASPL virtual device (fallback). *Status: Proposed — revisit at Phase 2.*
- **ADR-003 — Binaural:** custom SOFA-HRIR partitioned convolution + libmysofa, default dataset SADIE II; head tracking via CMHeadphoneMotionManager. *Status: Proposed.*
- **ADR-004 — Real-time ML:** BNNS Graph on the render thread; Core ML/Create ML off-RT only. *Status: Proposed.*
- **ADR-005 — Feature analysis:** build on vDSP (librosa as ISC reference) to avoid GPL MIR libs. *Status: Proposed.*
