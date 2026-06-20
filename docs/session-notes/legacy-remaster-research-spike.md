# Legacy-Recording Remaster — Research Spike

**Status:** Research spike (NOT a committed feature) · **Date:** 2026-06-20
**Method:** Two parallel agent passes — `audio-dsp-agent` (architecture/DSP) + `scientific-literature-researcher` (AI-era literature, 2020–2026), online review with citations.
**Scope note (LD-11):** This crosses into audio *restoration*, which is **out of scope as a shipping product feature**. Treated here as an exploratory spike to decide whether a future scope expansion is warranted. Nothing here is a sprint deliverable.

---

## 0. The question

> *"There's a lot of music recorded long ago (old instruments + old tech) that doesn't sound as good as new songs — even though we love the tracks, the motivation to listen is lost. Can we remaster on the fly, give it a different tone, make it more musical? Up to 3–6 s to start playing is fine."*

This is **on-the-fly "AI remastering" of legacy recordings**, not denoising. De-hissing is one sub-layer.

---

## 1. Executive conclusion

1. **Bandwidth extension is the #1 "sounds old" lever — bigger than hiss.** Old recordings sound *dull/small/dated* mainly because the highs are rolled off (hard wall at 6–8 kHz on pre-1960s, ~10–12 kHz on much pre-1980s material) and deep bass is missing — roughly a 20–30 dB energy gap in the top octave vs. a modern master. Fix the spectrum first; noise is secondary.

2. **The "3–6 s startup" defines a specific architecture: streaming process-ahead.** Not the real-time render contract, not unbounded offline. It works **iff the whole chain runs faster than real-time (RTF < 1)**; the head-start just pre-fills a ring buffer. Target **RTF ≤ 0.5** for thermal margin (math in §3).

3. **Two tiers fall out naturally:**
   - **Quick Remaster (streaming, RTF ≤ 0.5):** classical DSP + a light discriminative denoiser + **single-pass GAN bandwidth-extension** + match-EQ/loudness. Starts in 3–6 s. **Fully faithful, no hallucination.**
   - **Best Remaster (cached offline, Phase-1.5 lane):** heavy diffusion / stem-based processing, slower on first play, instant on replay.

4. **The hardware upgrade (M4/M5 → Mac Studio Ultra) moves the tier boundary the right way.** Stem separation (HTDemucs) and **one-step distilled diffusion SR (FlashSR)** cross *into* the streaming tier. But **multi-step diffusion (AudioSR, BABE-2, SonicMaster) stays offline regardless of hardware — that's an algorithmic limit (50–100 sampling steps), not a compute limit.**

5. **The central design tension is faithful vs. generative.** Diffusion can *hallucinate* "wrong" cymbal shimmer / phantom harmonics on a recording you know intimately — potentially worse than leaving the rolloff. Single-pass GAN SR (AERO) and pure-DSP matching are the safe defaults. Expose **"authenticity ↔ brightness"** as a user control.

6. **Biggest unknown: RTF on Apple Silicon is essentially unpublished.** Nearly every paper benchmarks on A100/CPU. The one solid datapoint is **HTDemucs ported to MLX at ~34× real-time on an M4 Max** (7-min song in ~12 s). → **The highest-value first engineering step is to benchmark our shortlist on the actual Mac via Core ML / MPS / MLX**, not trust paper numbers.

7. **There is no documented end-to-end *streaming* "legacy → modern" music system** (research or commercial — iZotope RX, LANDR, CrumplePop, etc. are all offline/GUI). A real-time streaming remaster would be **novel**.

---

## 2. What makes an old recording sound old (and the layer that fixes each)

| Symptom | Cause | Fix layer |
|---|---|---|
| Dull, veiled, "small" | HF rolloff (missing 8–20 kHz "air") | **R2 Bandwidth extension** |
| Thin, no weight | Missing deep bass (disc/tape limits) | **R2 Bandwidth extension** + virtual bass |
| Audible hiss/hum/crackle | Tape/circuit noise floor, disc surface | **R1 Restoration** (de-hiss/de-click) |
| Wrong/dated tonal balance | Era-specific cutting curves, dark mixes | **R3 Match-EQ** |
| Plays 6–12 dB quieter than modern | Pre-loudness-war masters | **R3 LUFS normalization** |
| Narrow / mono / flat | Mono or narrow-stereo capture | **R4 Width / spatial** |

### Processing order (matters for correctness)

```
Input
 → [R1a] De-click / de-crackle      (impulse removal first; clicks corrupt the noise estimate)
 → [R2]  Bandwidth extension        (extend spectrum before tone-shaping & before denoise)
 → [R1b] De-hiss                    (noise-floor estimate now valid across the full band)
 → [R3a] Match-EQ                   (spectral balance applied to the restored signal)
 → [R3b] LUFS normalize + true-peak limiter
 → [R4a] Mono→pseudo-stereo / M/S widening   (after de-hiss, so noise isn't widened)
 → [R4b] Harmonic exciter / virtual bass     (oversampled; gated above a noise threshold)
 → Output
```

---

## 3. The latency model — process-ahead math

Three regimes in the project:

- **Regime 1 — live render callback:** 128–512 samples, ~3–12 ms, no malloc/IO. The remaster chain does **not** run here.
- **Regime 2 — streaming process-ahead ("Quick Remaster"):** head-start `H` ∈ [3,6] s pre-fills a ring buffer, then sustain RTF < 1. **Primary new regime.**
- **Regime 3 — cached offline pre-pass ("Best Remaster"):** existing Phase-1.5 SSD-cache lane; first-play wait = full-track processing time, instant on replay.

**Process-ahead formula.** With head-start `H`, chain real-time factor `R` (processing-sec per audio-sec; `R<1` = faster than real-time):

```
Buffer at playback start:  B(0) = H / R           seconds of audio
Net buffer growth rate:    dB/dt = (1/R − 1)       seconds of audio per second
```

If `R < 1` the buffer **grows without bound** — it never starves. At `R = 1` you only have the fixed `H` margin (one thermal spike eats it). So:

> **Requirement: sustained RTF ≤ 0.7 (≈30% headroom). Design target ≤ 0.5.**
> Example: `H = 5 s`, `R = 0.5` → start with 10 s buffered, growing +1 s every second.

A low-water-mark fence (insert <2 ms silence / repeat last frame if buffer < 1 s) protects against transient spikes. Ring buffer = lock-free SPSC per the project's RT contract.

---

## 4. AI-era toolbox + RTF feasibility

RTF ranges below are for **M4 Pro laptop** → **M3 Ultra Studio**. **Bold** = the streaming-enabling few-step/distilled variant.
⚠️ **Most RTF figures are extrapolated from model size / sampling-step count — only HTDemucs has a measured Apple-Silicon number.** Treat as planning estimates, not guarantees.

| Method | Task | RTF (M4 Pro → M3 Ultra) | Tier | Faithful? |
|---|---|---|---|---|
| Classical DSP (match-EQ, LUFS, biquads, M/S, exciter) | tone/loudness/width | ~0.001–0.01 | **Stream** | ✅ Faithful |
| log-MMSE + decision-directed SNR | de-hiss | ~0.005 | **Stream** | ✅ Faithful |
| De-click (median / spectral interp) | de-crackle | ~0.02–0.05 | **Stream** | ✅ Faithful |
| DeepFilterNet-class (needs music retrain) | denoise | ~0.05–0.10 → 0.02–0.05 | **Stream** | ✅ Discriminative |
| Steinmetz/Reiss differentiable-DSP denoiser | denoise | ~0.05–0.15 → 0.03–0.08 | **Stream** | ✅ Faithful (DSP backbone) |
| **AERO** (complex-spec GAN, handles music) | bandwidth ext. | ~0.10–0.25 → 0.05–0.12 | **Stream** | ◑ GAN, bounded |
| **HTDemucs** (MLX) | stem separation | ~0.03–0.12 → 0.02–0.05 (**34× measured on M4 Max**) | **Stream** | ✅ Separation |
| **FlashSR** (1-step distilled diffusion) | bandwidth ext. | ~0.3–0.6 → 0.1–0.25 | **Stream on Ultra; borderline M4 Pro** | ⚠ Generative |
| AudioSR (≈50-step diffusion) | bandwidth ext. | ~5–15 → 2–5 | **Offline only** | ⚠ Generative |
| BABE-2 (diffusion "generative EQ") | restore + EQ | ~10–30 → 4–12 | **Offline only** | ⚠ Hallucinatory |
| SonicMaster (flow-matching DiT, all-in-one) | restore + master | ~20–50 → 8–20 (Euler-1 may cut this) | **Offline only** | ⚠ Hallucinatory |

**What moved with the hardware upgrade:** HTDemucs and FlashSR cross from offline-only (M1) into the streaming tier (M4+). **What can't move:** multi-step diffusion — even on an Ultra, a 4-min track is ~8–32 min of compute (AudioSR ~8–12 min; BABE-2 ~30 min). Only **distillation** (FlashSR's one step) breaks that wall.

---

## 5. Recommended tiered architecture

### Quick Remaster — streaming (starts in 3–6 s, target RTF ≤ 0.5)

```
[R1a] De-click           classical spectral interp        ~0.02
[R2]  Bandwidth ext.     AERO-class GAN (Core ML/MLX, off-RT → ring buffer)   ~0.10–0.20
[R1b] De-hiss            log-MMSE + DD-SNR (C++ kernel)    ~0.005
[R3a] Match-EQ           LTAS → min-phase biquads          ~0.001
[R3b] LUFS + limiter     libebur128 gain + true-peak       ~0.001
[R4a] Width              M/S pseudo-stereo                 ~0.001
[R4b] Exciter            oversampled NLD + virtual bass    ~0.005
                         ──────────────────────────────────
   Total: M4 Pro ≈ 0.13–0.22 · M3 Ultra ≈ 0.07–0.15   (well within budget)
```

- ML (BW-extension GAN) runs as **Core ML / MLX** inference in a background thread feeding the ring buffer — *never* in the render callback (same pattern as Phase-1.5 stem sep). Any small net that must sit in the process-ahead thread → **BNNS Graph**.
- All classical layers run in the **host-agnostic C++ DSP kernel**.
- Noise profile + match-EQ reference curve computed in a 2–3 s pre-analysis pass inside the head-start budget.

### Best Remaster — cached offline (Phase-1.5 lane)

Same layer structure, heavier algorithms: FlashSR or AudioSR for BW extension, optional BABE-2 generative EQ, **HTDemucs stem split → per-stem placement/EQ/exciter → re-sum**. Pre-pass on M3 Ultra: HTDemucs + FlashSR + classical ≈ **1–3 min** (acceptable as an explicit "Enhancing…" state); BABE-2/SonicMaster are "overnight/album" tier.

---

## 6. Faithful vs. generative — the key tension & risks

| | Faithful (attenuate/shape) | Generative (regenerate) |
|---|---|---|
| Examples | match-EQ, log-MMSE, AERO (bounded GAN), HTDemucs | AudioSR, FlashSR, BABE-2, SonicMaster |
| Risk | caps out on heavy damage | **invents content** — wrong shimmer/harmonics on a beloved take |
| Verdict | **Quick tier default** | Best/offline tier, opt-in, with a dry/wet blend |

**Top risks to design against:**
1. **BW-extension hallucination** on intimately-known recordings → expose dry/wet "authenticity ↔ brightness"; test on tracks the listener knows by heart.
2. **Match-EQ overcorrection** stripping era-authentic character (a deliberately dark 1950s jazz cut) → cap to ±6 dB/octave-band; gentle/balanced/aggressive presets; confirm reference, don't auto-apply.
3. **Pseudo-stereo mono-incompatibility** → require L+R sum within ±1 dB of original mid-band; prefer M/S over Haas.
4. **Non-stationary noise** (reel changes, speed drift) breaks stationary log-MMSE → Martin minimum-statistics fallback.

---

## 7. License notes (LD-9) — verify before shipping any of these

- **Matchering** (the obvious match-EQ/loudness reference impl) is **GPL-3.0**, *not* MIT (one agent misstated this). → **Reference-only**: study it, **reimplement the LTAS-match + RMS + limiter idea cleanly** (it's simple), don't ship its code.
- **Model weights ≠ code license.** AERO / FlashSR / Demucs code is MIT/Apache, but anything trained on **MUSDB18-HQ** inherits **non-commercial** weight terms → reference-only weights; we'd retrain on permissible data to ship.
- DeepFilterNet code Apache-2.0 (weights speech-trained → not directly usable on music).

---

## 8. Recommended POC (Quick Remaster first; Python prototype)

Build order — each step has an offline verification + a listening A/B on ~5 test tracks spanning 1930s–1970s:

1. **Classical backbone** (`scipy` + `librosa` + reimplemented match-EQ + `libebur128`): match-EQ + LUFS + limiter + M/S width. Establishes the faithful "floor." *Verify:* output LUFS within ±0.5 LU; plot LTAS before/after; mono-sum within ±1 dB.
2. **De-hiss** — slot log-MMSE + decision-directed SNR after de-click. *Verify:* noise-only null test, residual analysis, spectral-kurtosis (musical-noise proxy).
3. **Bandwidth extension bake-off** — AERO vs nuwave2 vs FlashSR (where weights available). *Verify:* HF energy 10–16 kHz before/after, ViSQOL (music), **explicit hallucination listening check**.
4. **RTF measurement** on the real target Mac — confirm sustained ≤ 0.5; profile each layer's share. **This is the single most important data point** (paper RTFs are NVIDIA/CPU).
5. **Process-ahead simulation** — 5 s chunks, H = 5 s, log buffer depth B(t) ≥ 1 s for a full track.

**Accept criteria:** RTF ≤ 0.5 (M4 Pro); B(t) ≥ 1 s throughout; audible brightness/weight/loudness gain on all 5 tracks; **no warble, no audible hallucination**; mono-sum within ±1 dB.

---

## 9. References (consolidated)

**Bandwidth extension / super-resolution**
- Mandel, Tal, Adi (2023) — *AERO: Audio Super-Resolution in the Spectral Domain.* ICASSP. arXiv:2211.12232 · github.com/slp-rl/aero
- Im & Nam (2025) — *FlashSR: One-step Versatile Audio Super-Resolution via Diffusion Distillation.* ICASSP. arXiv:2501.10807
- Liu et al. (2024) — *AudioSR: Versatile Audio Super-Resolution at Scale.* ICASSP. arXiv:2309.07314
- Han & Lee (2022) — *NU-Wave 2.* INTERSPEECH. arXiv:2206.08545
- Moliner & Välimäki (2022) — *BEHM-GAN: Bandwidth Extension of Historical Music using GANs.* IEEE/ACM TASLP. arXiv:2204.06478

**Mastering / tone-matching**
- Grechin — *Matchering 2.0* (GPL-3.0, reference-only). github.com/sergree/matchering
- Koo et al. (2025) — *ITO-Master: Inference-Time Optimization for Mastering.* ISMIR. arXiv:2506.16889
- "SonicMaster: Controllable All-in-One Music Restoration and Mastering" (2025). arXiv:2508.03448

**Restoration / denoise**
- Moliner & Välimäki (2022) — *Two-Stage U-Net for High-Fidelity Denoising of Historical Recordings.* ICASSP. arXiv:2202.08702
- Moliner, Lehtinen, Välimäki (2023) — *CQT-Diff: Solving Audio Inverse Problems with a Diffusion Model.* ICASSP. arXiv:2210.15228
- Moliner et al. (2024) — *BABE-2: A Diffusion-Based Generative Equalizer for Music Restoration.* DAFx. arXiv:2403.18636
- Steinmetz, Walther, Reiss (2023) — *High-Fidelity Noise Reduction with Differentiable Signal Processing.* AES 155. arXiv:2310.11364
- Ephraim & Malah (1984/1985) — MMSE-STSA / log-MMSE. IEEE TASSP.
- Martin (2001) — Minimum-statistics noise estimation. IEEE TSAP.
- Valin (2018) — *A Hybrid DSP/Deep Learning Approach to Real-Time Full-Band Speech Enhancement (RNNoise).* IEEE MMSP, arXiv:1709.08243 · Schröter et al. (2022–23) — *DeepFilterNet 1/2/3* (DFN1 ICASSP'22 arXiv:2110.05588; DFN2 IWAENC'22; DFN INTERSPEECH'23).

**Inference cost / pipelines / survey**
- Rouard, Massa, Défossez (2023) — *Hybrid Transformers for Music Source Separation (HTDemucs).* ICASSP; MLX Apple-Silicon port (~34× RT on M4 Max, community benchmark).
- Lemercier, Richter, Welker, Moliner, Välimäki, Gerkmann (2025) — *Diffusion Models for Audio Restoration.* IEEE Signal Processing Magazine. arXiv:2402.09821

---

## 10. Open questions / decisions for the founder

1. **Scope:** does this graduate from spike to a real roadmap item, given it's LD-11-adjacent? (It's also close to the core "make music sound better" mission.)
2. **Tier priority:** ship the **Quick streaming** tier first (faithful, novel, fits the 3–6 s UX), or prototype the **Best cached** tier for max quality?
3. **Faithful-only, or allow generative with a blend?** Determines whether diffusion BW-extension is in scope at all.
4. **Next action:** build the Python POC (§8) — recommended, since the decisive unknown (Apple-Silicon RTF) can only be answered by measurement.
