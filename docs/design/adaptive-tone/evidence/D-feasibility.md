# Brief D: on-device feasibility of an AI that reads ahead and suggests EQ and tone

*Track D, 2026-10-10. Owns RO8 (on-device feasibility), the tools half of RO1 (sensing) and the architecture half of RO7 (authority and safety). Read-only on the repo; every benchmark ran in the scratchpad. Machine: Apple M4 Pro (10 performance + 4 efficiency cores), 24 GB, macOS 26, Python 3.12.*

> **Erratum (main thread, later on 2026-10-10).** Two EQ1c commits landed on `feat/s10-8-eq` while this brief was being written: `811a59d` (the loudness-neutral gain is live; `Realizer.mm:410,479` now write `outputGainDb`) and `8faff1a` (`Sources/TrackLoudnessKit/TrackLoudnessAnalyzer.swift` exists). So the claims below that "Compare is not loudness-matched today" and "the Swift `TrackLoudnessAnalyzer` doesn't exist" are **superseded**. EQ2 (the bridge cut-over that retires `EQSafetyClamp`) is still open. The bench scripts' paths point at the session scratchpad; they are kept here as a record.


**Legend.** External claims carry the protocol grades A/B/C/D/U. **M** marks a measurement I made this session. Measurements are not peer-reviewed, and the n is stated each time. **E** marks my own estimate, which no measurement backs. Repo claims cite `file:line`. Source IDs (D01…, M01…) point to the evidence table in §4.

---

## 1. TL;DR

1. **Compute is not the constraint.** On an M4 Pro, every candidate in the "fast tier" analyses a whole 3.7-minute track in under a second:
   - Apple SoundAnalysis: 0.50 s [M01];
   - Discogs-EffNet (genre, mood and a 1280-d embedding): 0.4–0.8 s including decode [M02];
   - Audiobox Aesthetics on the GPU (MPS): 0.90 s [M04].

   Read-ahead of the current and next track is therefore cheap, even on the M1 Pro floor (the 2–4× slowdown is my estimate, E). Structure analysis is the expensive tier. All-In-One needs source separation [D17], and SongFormer needs two large self-supervised encoders [D18]. Expect 10 s to a few minutes per track on a Mac (E).
2. **The licences are the constraint.** Most music-specific weights are **non-commercial**:
   - Essentia models: CC BY-NC-SA 4.0 [D02]. The LICENSE file itself says "NonCommercial-NoDerivatives", which is inconsistent [D03];
   - MAEST: CC BY-NC-SA 4.0 [D15];
   - MERT: CC-BY-NC-4.0 [D13];
   - MuQ: CC-BY-NC 4.0 [D14];
   - madmom models: CC BY-NC-SA [D20].

   Essentia's code is **AGPL-3.0** [D01]. MAEST's code is AGPL-3.0 too [D16]. Both are fine for a personal/OSS build. For a future commercial release, AGPL and NC are hard blockers unless the work is licensed. The permissive options are:
   - Audiobox Aesthetics: CC-BY-4.0, code and weights [D05, D07];
   - LAION-CLAP: CC0 code and weights; `larger_clap_music` is Apache-2.0 [D08–D10];
   - MS-CLAP: MIT code, MS-PL weights [D11, D12];
   - YAMNet: Apache-2.0 [D25];
   - Apple's frameworks.
3. **The priority probe: Audiobox Aesthetics is a weak and exploitable critic of EQ, not an objective** [M05, M06]. I ran it on 3 music clips × 14 loudness-matched EQ variants, with controls and a ±12 dB sweep.
   - **What it gets right.** A harsh +9 dB peak at 3 kHz lowers Production Quality (PQ) in 9 of 9 windows: −0.35 and −0.39 on the two real recordings.
   - **No optimum.** PQ rises *monotonically* with a 6 kHz treble shelf all the way to +12 dB on every clip. It also prefers a deep 3 kHz *cut* (best at −9 to −12 dB). An optimiser that maximised PQ would push Air to the ceiling and scoop the presence region.
   - **Blind spots.** It is almost blind to EQ on the cleanly produced clip (every effect ≤ 0.03). It resamples to 16 kHz mono, so it cannot hear above 8 kHz or hear stereo width.
   - **Noise.** It is deterministic on identical audio. But a ±3 dB shelf moves PQ by about as much as sliding the excerpt by 1 s (≤ 0.29), or by a 1–6 dB level error.
4. **Sensing spectral balance needs DSP, not ML.**
   - The Essentia "bright/dark" timbre head barely moves over ±12 dB of treble: 0.39–0.43 [M03].
   - SoundAnalysis has no genre or mood classes at all: 303 labels, of which only "music", singing and instruments are musical [M01].
   - The repo already has the right DSP sensor. `TrackLoudnessProfiler` keeps the K-weighted spectrum of a whole track in 1/24-octave bands, every 100 ms (`Sources/AudioDSP/Loudness/TrackLoudnessProfile.h:6-20`). That is a read-ahead spectral-balance-over-time feature, already built and gated.
5. **The engine hooks mostly exist; three prerequisites do not.**
   - **What exists.** A suggested Tone vector can ride the one EQ dispatch: `EQViewModel.publish()` → `Realizer::setPendingEq` → the S2 glide (`EQViewModel.swift:195-198`, `AUAudioUnit.mm:423-439`, `Realizer.mm:150-177`). The RT glide accepts τ up to 2 s (`EQModule.cpp:23-24`). The loudness-neutral gain rides the same one-pole (`EQModule.h:14-16`), so a slow, level-matched section glide needs only a "glide hint" in the intent.
   - **What is missing.**
     - The Swift `TrackLoudnessAnalyzer` is not built: only the C++ profiler and its C-ABI exist.
     - The Realizer never writes `outputGainDb`, so **Compare is not loudness-matched today** (`TargetState.h:23-24`; no writer in `Realizer.mm:287-305`).
     - The Arbiter and the hearing-safety clamps are design only (`architecture.md:139`, `:275`).
6. **A/B.** Once EQ1c and EQ2 land, the Compare machinery can host a fair, loudness-matched A/B with modest changes:
   - the −ΔL predictor works for *any* curve;
   - the switch is a gapless 10 ms glide.

   Compare is currently binary (curve vs Off), sighted, and sequential over changing music. "Better / not" needs:
   - curve-vs-curve;
   - unlabelled arms;
   - a replayed excerpt;
   - Intensity held at 0 or the normaliser frozen during the trial (§3, RO8-4).

---

## 2. Findings by RO

### RO1 (tools half): what each tool would tell us about a track

| Tool | Outputs | Size | Code licence | Weights licence | Mac path | Compute per ~4-min track | Src |
|---|---|---|---|---|---|---|---|
| **In-repo `TrackLoudnessProfiler`** | K-weighted 1/24-octave power per 400 ms block (100 ms hop), gated LUFS, ΔL for any curve | ≈2.5 MB per profile | repo | n/a | C++/vDSP, built | ≈0.5 s FFT + 0.2–0.4 s decode on M1 (repo estimate) | `TrackLoudnessProfile.h:6-35`; `engine-plan.md:233-243` |
| **Apple SoundAnalysis (built-in v1)** | 303 sound labels; music-related ones only "music", singing, rapping, choir and instruments; **no genre/mood**; 3 s windows, 50 % overlap | system | Apple SDK | Apple | native, Core ML | **0.50 s / 223 s** [M01] | D23, M01 |
| **Create ML `MLSoundClassifier`** | your own classes (e.g. themes) trained from ≥10 examples per class; exports a Core ML model for `SNClassifySoundRequest` | small | Apple SDK | yours | native | ≈ SoundAnalysis (E) | D24 |
| **Discogs-EffNet** (Essentia) | 400 Discogs styles, 1280-d embedding ≈1 per s; heads: 56 mood/theme, 87 genre, 40 instruments, approachability, engagement, danceability, timbre, acoustic/electronic, voice/instrumental | 18.4 MB `.pb`, 18.0 MB official ONNX; heads 0.5–2.7 MB | AGPL-3.0 (Essentia) | CC BY-NC-SA 4.0 (page) / "BY-NC-ND" (LICENSE file) | essentia-tensorflow arm64 wheel (cp311–313, 115 MB); ONNX via onnxruntime (MIT) | **TF 0.66 s, ONNX-CPU 0.23 s, +0.09 s decode** [M02] | D01–D04, M02 |
| **MAEST** | 400 / 519 Discogs styles, transformer embeddings; 5–30 s inputs, 16 kHz | 86.9 M params, 347.5 MB | AGPL-3.0 | CC BY-NC-SA 4.0 | PyTorch/MPS; ONNX listed by Essentia | 1–3 s MPS (E) | D02, D15, D16 |
| **LAION-CLAP** (music checkpoints) | 512-d joint audio–text embedding; zero-shot tags or theme by text prompt; 48 kHz | 2.35 GB `.pt` (music); HF `larger_clap_music` 776 MB | CC0-1.0 | CC0 (HF metadata); `larger_clap_music` Apache-2.0 | PyTorch/MPS; no Core ML port found | 1–3 s MPS (E) | D08–D10 |
| **MS-CLAP 2023** | audio–text embedding, captioning (clapcap) | 690 MB | MIT | MS-PL | PyTorch/MPS | 1–3 s (E) | D11, D12 |
| **MERT-v1-95M / 330M** | 13 layers × 768-d features at 75 Hz; 24 kHz; trained on 5 s contexts | 95 M (378 MB) / 330 M | U | CC-BY-NC-4.0 | PyTorch/MPS; no MLX or Core ML port found | 95M ≈1–2 s MPS (E, by analogy with the 104 M WavLM in M04) | D13, Q3 |
| **MuQ / MuQ-MuLan** | SSL embeddings / music–text similarity; 24 kHz only | ~300 M (1.33 GB) / ~700 M | MIT | CC-BY-NC 4.0 | PyTorch/MPS | 3–15 s (E) | D14 |
| **Audiobox Aesthetics** | 4 scores, ~1–10: Production Quality, Production Complexity, Content Enjoyment, Content Usefulness; 16 kHz **mono**, 10 s windows, averaged | 103.9 M params (counted), 415.5 MB | CC-BY-4.0 (parts MIT) | CC-BY-4.0 (HF card) | PyTorch **MPS works**; no Core ML / ONNX port found | **0.90 s MPS, 7.2 s CPU per 223 s** [M04] | D05–D07, M04–M06 |
| **All-In-One** (Kim & Nam) | tempo, beats, downbeats, segments with 10 labels (intro/verse/chorus/bridge/inst/solo/outro/break/start/end); **needs Demucs stems** | 8-fold ensemble (size U) | MIT | not stated (U) | PyTorch; NATTEN auto-installs on macOS per README | 73 s per 10 songs on an RTX 4090 (C); Mac 30 s–3 min (E) | D17 |
| **SongFormer** (2025) | boundaries + 8 labels (intro, verse, pre-chorus, chorus, bridge, inst, outro, silence) | 104.5 MB head + 2.76 GB of SSL encoders (MuQ + MusicFM) | CC-BY-4.0 | not stated (U); depends on MuQ (NC) | PyTorch, GPU-oriented | "2–4 s per song" on an L40 (C); Mac 10–30 s (E) | D18 |
| **madmom** | beats, downbeats, tempo, onsets, key, chords | small | BSD | CC BY-NC-SA 4.0 | CPU; last PyPI release 2018-11 | 5–20 s (E) | D20, D28 |
| **MSAF** | classic (non-DL) boundary and label algorithms | n/a | MIT | n/a | CPU; PyPI 0.1.80 (2023) | seconds (E) | D21, D28 |
| **YAMNet / PANNs** | 521 / 527 AudioSet labels, **including 34 genres** (Pop, Rock, Jazz, Classical, Electronic…) | YAMNet small (U) | Apache-2.0 / MIT | Apache-2.0 / U | YAMNet has a 3rd-party Core ML port (U) | <1 s (E) | D25, D26 |
| **Matchering** | DSP (no ML): matches RMS, frequency response, peak and width to a **reference track** | n/a | GPL-3.0 | n/a | Python | seconds (E) | D22 |
| **Era** (He et al. 2024) | decade class; 67.5 % exact, 91.7 % within ±1 decade, audio only, on MSD | n/a | not released (U) | — | research only | — | D27 |

**What the tools can tell us, by property:**
- **Spectral balance (the property an EQ acts on).** Measure it with DSP. The repo's profiler gives a band spectrum per 100 ms for the whole track. Learned heads do not track it [M03]: the "bright" probability moved 0.39 → 0.43 for −12 → +12 dB of 4 kHz shelf. Embeddings shift monotonically along *one* direction under a filter, but the displacement is high-dimensional and does not linearise [D29, B].
- **Genre / mood / theme.** Discogs-EffNet heads are cheap and broad. On this library's material, though, top-1 confidence was only 0.11–0.16. Its picks for the two clips taken from Sri Lankan recordings were "Pop---Vocal", "Pop---Chanson" and "Folk"; the generated band clip came out "Pop---J-pop" [M02]. The taxonomies are Western-catalogue-trained. CLAP text prompts, or a Create ML classifier trained on the founder's own themes, may fit better (untested, U).
- **Structure.** All-In-One and SongFormer give labelled sections. Both are heavy, and SongFormer's weight licence is unstated. A cheap alternative is a novelty curve over the profiler's 100 ms spectra or the EffNet embeddings (≈1 Hz), which gives boundaries but no labels (E).
- **Era.** No released model. Use the `tracks.year` tag (`Schema.swift:174`) plus DSP proxies such as bandwidth, crest factor and loudness.
- **"Quality".** Audiobox Aesthetics is the only permissive option, with the caveats in RO8-3.
- **Bandwidth blind spot.** Every learned model here resamples to 16 kHz (EffNet, MAEST, Audiobox, YAMNet) or 24 kHz (MERT, MuQ) [D02, D06, D13, D14]. They cannot see the Air region (> 6 kHz) properly, so Air suggestions must come from DSP.

### RO7 (architecture half): how a model-driven contributor composes, and what it must never touch

**What exists today (the shipped path, not the design).**
- One dispatch: `EQViewModel.edit` → `setCurrent` → `publish()` sends `points` and `isOn && !isComparing` (`EQViewModel.swift:173-198`).
- `points = clamp(base + Σ tone·weight, ±12)` (`EQCurve.swift:43-52`).
- The bridge clamps once more with the old `EQSafetyClamp` until EQ2 (`AudioEngineBridge+EQControl.swift:27`), and calls the C-ABI.
- The Realizer rejects non-finite input, clamps to ±12, coalesces, designs and is the sole publisher (`Realizer.mm:150-177, 242-305, 336-349`).
- There is no Arbiter. Its rules (lock, additive / conservative, proportional clamping) and the §11 clamps are design only (`architecture.md:161-171`, `:273-287`).

**Recommended composition (recommended option first).**
1. **Recommended: a separate "suggestion" layer in the control plane, summed before the one dispatch.**
   - played = clamp(base + userTone + **s·autoTone**, ±12), where s = the user's "AI amount" × confidence;
   - autoTone is held to ±3 dB per region, the §11 "low-confidence magnitude" (`architecture.md:287`);
   - it never writes into the user's `base` or Tone. Save does not bake it in unless the user accepts it;
   - it is the minimal form of the planned typed contributor. When the Arbiter lands, the layer becomes the "content-adaptive" contributor under the Arbiter's lock rule: user-confirmed bands win on direction (`architecture.md:165`).
2. Alternative: write into the user's Tone sliders. **Not recommended.** The AI would fight the user's own control and pollute per-output memory and Save.

**Bounds that compose with the rest of the chain.**
- **Loudness.** The AI's curve must be loudness-neutral through the same −ΔL predictor (decision 26). Any change it makes is then a shape change, not a level change. This matters twice over: louder is preferred by listeners, and by the predictor too (+1 dB raised Content Enjoyment by up to 0.055 [M05]).
  - The normaliser (−16 LUFS, 1 dB/s slew; `LoudnessModule.h:48-53`) is absent at Intensity 0 (P1; `DSPKernel.cpp:175-179`), so −ΔL is the only level control there.
  - A section-specific curve should be compensated over *that section's* blocks. The profile keeps every 100 ms block (`TrackLoudnessProfile.h:85-90`), so this is a block-range variant of `predictLoudnessChangeDb` (`:107-110`) (E).
- **Limiter.** Decision 29's ceilings apply: −0.1 dBTP on wired outputs in the EQ-only path, −1 dBTP elsewhere and on Bluetooth (`amendments.md:18-36`). AI boosts add limiter load, up to +4.29 dB on loud masters at Intensity 0 (`engine-plan.md:276-281`). The suggestion's objective should penalise predicted limiting. The planned "per-curve peak scan" (`amendments.md:35-36`) would supply that.
- **Hearing safety.** Until §11 is built, the contributor enforces its own caps: ±3 dB per Tone region, and no positive sum beyond the user's own curve in the 3–5 kHz zone (`architecture.md:281`). This is my recommendation; the §11 table is the source.
- **Cadence.** The KPI is "never perceived as the EQ moving" (`architecture.md:267`). Change only at section boundaries, with a slow glide (RO8-3 hooks) and hysteresis.

**What it must never touch.**
- **Pure Mode.** No analysis and no processing (`amendments.md:59`). That path bypasses the DSP graph entirely (`architecture.md:86`).
- **The bit-perfect anchor.** At Intensity 0 with EQ Off, P0 needs `eqIdentity` held for 2 s (`DSPKernel.cpp:132-152`). An AI suggestion must not switch the EQ on: only a user edit does that (`ui-plan.md:206`).
- **The limiter's ceiling, the normaliser's target, Intensity, crossfeed and the output device.** Recommendation: EQ/Tone authority only for R1, with no "controls the entire playback".
- **The render thread.** Inference stays off-RT (ADR-004 reserves BNNS Graph for RT ML, and none is needed; `architecture.md:318, 375`).
- **ADR-005 conflict.** ADR-005 says vDSP features "avoid GPL MIR libs" (`architecture.md:376`). Shipping Essentia (AGPL) would reverse it. Recommended instead: the official ONNX weights through onnxruntime (MIT), or a Core ML conversion, with the 96-band mel front end rewritten in vDSP. The weights stay NC either way.

### RO8: on-device feasibility

**RO8-1. Benchmarks (all M, M4 Pro).** Scripts and raw outputs are in `scratchpad/bench-scripts/` and `scratchpad/bench-results/`. The clips are copies of repo research audio, because `test-data/` holds only ≤152-byte stub fixtures (the largest file is 152 B; `test-data/README.md` says fixtures are generated at test time):
- A: `research/reimagine-poc/data/seetha_excerpt.wav` — an older Sri Lankan recording, 45 s, 44.1 kHz;
- B: `research/reimagine-poc/out/backing/turbo_band.wav` — a generated band mix, 45 s, 48 kHz;
- C: `research/legacy-remaster-poc/out/tuned.wav` — a full 223 s remastered track, 44.1 kHz/24-bit.

| ID | What | Result |
|---|---|---|
| M01 | Apple SoundAnalysis built-in, whole track C | 303 labels; 0.50 s for 223 s (147 windows); top: music 0.8, singing 0.4 |
| M02 | Discogs-EffNet, track C | decode + resample 0.09 s; TF embed 0.66 s; 4 heads 0.036 s; ONNX-CPU 0.23 s (+0.07 s mel); **ONNX CoreML EP 11.4 s** (dynamic batch shape; ORT documents that dynamic shapes hurt the CoreML EP [D31]) |
| M03 | EffNet timbre head vs a 4 kHz shelf, −12…+12 dB, RMS-matched | P(bright): A 0.40→0.43, B 0.47→0.49, C 0.41→0.43 — insensitive |
| M04 | Audiobox Aesthetics timing | MPS: 0.14 s per 30 s clip, **0.90 s per 223 s**; CPU: 0.31 s per 30 s, 7.2 s per 223 s (the package batches all windows at once); load 1.25 s; MPS and CPU agree to 1e-5 |

**RO8-2. Audiobox Aesthetics EQ-sensitivity probe (M05, M06).**

*Method.*
- **Excerpts.** One 30 s excerpt per clip (A and B from 5 s, C from 60 s).
- **EQ.** RBJ biquads at the native rate, each variant matched to the flat excerpt's BS.1770 integrated loudness with pyloudnorm.
- **Scoring.** Per 10 s window, using the package's own window and hop.
- **Controls.** An exact repeat; level-only changes (no matching); and the excerpt shifted by 0.5 / 1 / 2 s.

The PQ columns are the change from flat. "Agree" counts the windows (of 9) where the PQ change has the same sign.

| Variant (match gain A/B/C, dB) | ΔPQ A | ΔPQ B | ΔPQ C | Agree | ΔCE mean | ΔCU mean |
|---|---|---|---|---|---|---|
| flat — PQ / CE | 5.44 / 6.88 | 8.44 / 7.90 | 5.53 / 7.00 | — | — | — |
| bass +3, 150 Hz low shelf (−0.6/−1.3/−0.5) | +0.03 | +0.01 | +0.03 | 6/9 | +0.05 | +0.02 |
| bass +6 | +0.03 | +0.01 | +0.03 | 6/9 | +0.09 | +0.00 |
| bass −3 | −0.03 | −0.01 | −0.03 | 6/9 | −0.06 | −0.02 |
| bass −6 | −0.05 | −0.02 | −0.08 | 6/9 | −0.12 | −0.04 |
| treble +3, 6 kHz high shelf | +0.10 | +0.00 | +0.19 | **9/9** | +0.02 | +0.07 |
| treble +6 | +0.22 | +0.01 | +0.37 | **9/9** | +0.05 | +0.13 |
| treble −3 | −0.07 | −0.01 | −0.14 | **9/9** | −0.02 | −0.06 |
| treble −6 | −0.12 | −0.01 | −0.26 | **9/9** | −0.03 | −0.12 |
| tilt +3 (bright, 1 kHz pivot) | −0.18 | +0.02 | −0.13 | 5/9 | −0.13 | −0.14 |
| tilt −3 (dark) | +0.05 | −0.02 | −0.05 | 6/9 | +0.09 | +0.05 |
| **harsh +9 dB at 3 kHz, Q 1.4** (−3.4/−2.4/−3.4) | **−0.35** | −0.02 | **−0.39** | **9/9** | −0.09 | −0.29 |
| mud +6 dB at 250 Hz | +0.03 | −0.03 | −0.09 | 7/9 | **+0.09** | −0.04 |
| air +6, 10 kHz shelf (above the model's 8 kHz Nyquist) | +0.04 | +0.01 | +0.13 | 8/9 | +0.01 | +0.03 |

| Control | A | B | C |
|---|---|---|---|
| exact repeat, all axes | 0.000 | 0.000 | 0.000 |
| level +1 dB, no matching: ΔPQ / ΔCE | +0.015 / +0.028 | −0.010 / −0.010 | +0.028 / +0.055 |
| level −6 dB: ΔPQ / ΔCE | −0.12 / −0.21 | +0.06 / +0.05 | −0.14 / −0.41 |
| excerpt shifted 0.5 / 1 / 2 s: ΔPQ | −0.05 / −0.29 / −0.17 | +0.01 / +0.01 / +0.02 | −0.05 / −0.04 / −0.08 |
| SD of PQ across the 3 windows (flat) | 0.16 | 0.05 | 0.27 |

*Sweep, −12…+12 dB, loudness-matched (M06): where PQ peaks.*

| EQ move | A | B | C |
|---|---|---|---|
| 6 kHz high shelf | +12 dB (5.26 → 5.93) | +12 dB (8.41 → 8.46) | +12 dB (5.11 → 6.19) |
| 150 Hz low shelf | +6 dB | +6 dB | +3 dB |
| 3 kHz peak | **−12 dB** | 0 dB | **−9 dB** |

Content Enjoyment rises steadily with bass all the way to +12 dB on every clip.

*Answers to the coordinator's questions.*
- **Monotonic and plausible?** Partly.
  - *Plausible:* PQ falls under the harsh 3 kHz peak (9/9 windows) and falls with treble cuts.
  - *Not plausible:* PQ never peaks for treble; it keeps rising to +12 dB. It favours a 9–12 dB cut at 3 kHz. CE goes **up** with +6 dB of mud. Effects are near zero on the cleanly produced clip B. It does register an "air" shelf above its own 8 kHz Nyquist (+0.13 on C), but only through the shelf's skirt below 8 kHz.
  - *So:* as an objective it rewards brightness and presence scoops without limit. It is a usable *harshness or dullness alarm* on older recordings, and nothing more.
- **Bigger than the noise?** On *identical, aligned, level-matched* audio, yes: scoring is deterministic, and treble and harsh effects keep their sign in 9/9 windows. Bass, tilt and mud effects (|Δ| ≤ 0.18) do not (5–7/9). Across *different* audio the differences drown: a 1 s excerpt shift moved PQ by up to 0.29, and a ±1 dB level error by up to 0.03 PQ / 0.06 CE. Any use must be paired, on the same audio, at matched level.
- **Speed.** One 30 s clip: 0.14 s on MPS, 0.31 s on CPU. A whole 223 s track: 0.90 s on MPS. MPS worked with no changes.
- **Downloads.** Checkpoint 415.5 MB plus a torch / torchaudio venv (887 MB installed), within the 1.5 GB cap.
- **Not shown.** Whether PQ deltas track *listener* preference for EQ on the same track. The paper reports a music PCC with human overall quality of only 0.464 (PAM-music), and nothing on EQ [D06]. That is RO2's question.

**RO8-3. Repo hooks.**

*Pre-analysis and features today.*
- **Track loudness profile.** `TrackLoudnessProfiler` + predictor + C-ABI (`TrackLoudnessProfiler.h:22-35`, `TrackLoudnessBridge.h:12-18, 146-151`). Specified owner: a Swift `TrackLoudnessAnalyzer` actor, ≤ 2 jobs (current + next), prefix first, none in Pure Mode, a cache keyed by file identity, switching at the audible seam (`amendments.md:53-79`). **That actor does not exist yet**: grep finds only the C++, the C-ABI and the tests.
- **Live normaliser.** `LoudnessModule`: a BS.1770 worker thread fed from an SPSC ring, post-blend, 1 dB/s slew, a 50 ms RT ramp (`LoudnessModule.h:3-27, 48-53`). It is causal, not read-ahead.
- **Meters.** Display-grade, post-EQ: a 4096-pt FFT, 44 bands from 40 Hz to 5.7 kHz (`SpectrumAnalyzer.swift:15-28`; taps at `AudioEngineBridge+Graph.swift:145, 183, 205`). Not usable as an analysis input.
- **Library scan.** Metadata and artwork only, in a bounded sliding pool (≤ 6 in flight; `MetadataScanner.swift:55-92`). No decode. That pool is the pattern a library-wide analysis pass would reuse.
- **Cached per-track features.** None. `tracks` holds `file_size`, `mtime`, `content_hash`, `duration_ms`, `year`, `sample_rate` (`Schema.swift:157-188`).

*Where an analysis cache would live (recommended first).*
1. **Small features** in a new LibraryStore table `track_analysis`:
   - contents: embedding f16 ≈ 2.5 KB, tags, sections, PQ, the suggested Tone vector, `analyzer_version`, a file signature;
   - added by an additive migration v8 in the `MigrationID` pattern (`Schema.swift:54-81`), with `eraseDatabaseOnSchemaChange = false` (`LibraryStore.swift:308`);
   - versioned like `derived_version` (`LibraryStore+DerivedData.swift:19-40`);
   - it is a derived cache, so dropping and rebuilding it is fine.
2. **Large per-block spectra** (≈2.5 MB per track) in a content-addressed file cache beside the artwork cache (`AppDataLocation.swift:31`, the `ArtworkCache.swift:1-10` pattern), or simply recomputed (≈1 s).
3. **"Better / not" feedback** is *user* data. Store it in its own durable table, never in the derived cache.

*How a suggested Tone vector reaches the engine today.*
- Tone → points: `EQToneRegion.bandWeights` (`EQToneRegion.swift:20-24`) via `EQCurve.points` (`EQCurve.swift:43-52`). Presets are already Tone vectors (`EQBuiltInPreset.swift:62-73`).
- Points → engine: `EQViewModel.publish()` (`:195-198`) → `AudioViewModel.publishEQ` (`AudioViewModel.swift:373-375`) → `AudioEngineBridge.publishEQ` (`+EQControl.swift:15-35`, still `publishEQBandGains` + `EQSafetyClamp` until EQ2) → `publishEQ` C-ABI (`AUAudioUnit.mm:423-439`) → `Realizer::setPendingEq` (`Realizer.mm:150-177`) → drain → `realizeEq` (designer + τ rule, `:287-305`) → `publishCanonical`, the only `publishTargetState` (`:336-349`) → the kernel's EQModule adopts it on the next block (`DSPKernel.cpp:117-120`).

*How ramps work, and what a slow section glide needs.*
- **EQ glide (S2).** One one-pole per sample on each band's finished (k, m1). Every intermediate state is a stable bell, and the transition does not swell past the louder endpoint (`EQModule.h:8-16`). The τ rule is 10 / 40 / 160 ms (`EQTargets.h:15-46`). The RT clamp is τ ∈ [1 ms, 2 s] (`EQModule.cpp:23-24, 65-71`).
- **Output gain on the same one-pole.** `outputGainDb` (the −ΔL gain) rides the same one-pole as the bells (`EQModule.cpp:103-116`). That is why the level cannot jump mid-glide.
- **Other ramps.** Amendment 15 makes each band follow its own τ (`amendments.md:131-136`). Intensity uses its own 32 ms one-pole (`DSPKernel.cpp:20-22`), and so does crossfeed (`CrossfeedModule.cpp:11`). The old 32 ms `masterGainLinear` is gone: it was the cause of the v1 +5.4…+6.9 dB overshoot (`engine-plan.md:194-197`).
- **What a slow section glide needs (E).**
  1. A `glideSeconds` hint in `Realizer::EqIntent` (`Realizer.h:79-83`), honoured as max(τ rule, hint) up to 2 s. A one-pole at τ = 1.5 s settles 95 % in ≈4.5 s.
  2. The Realizer computes −ΔL for every target, so the gain glides in lockstep. This is the missing EQ1c Realizer part.
  3. Schedule from the control plane. Position comes from `currentPlaybackPosition()` (`AudioEngineBridge+Playback.swift:241-263`), polled at 20 Hz (`AudioViewModel+SpectrumTimer.swift:8`). Timing jitter of ±50 ms does not matter for a multi-second glide, so no sample-timestamped target is needed.
  4. At a gapless seam, switch with the profile at the audible seam (`AudioEngineBridge+Gapless.swift:191`, `amendments.md:63-67`).

  The alternative, interpolating intermediate Tone vectors in steps, is not recommended: it costs one design per step and stacks with the τ rule.

**RO8-4. A/B mechanics (decisions 26 and 28).**
- **Today.** Compare is hold-to-hear-without-EQ (`EQViewModel.swift:202-218`; `ui-plan.md:209-235`). The engine sees `isOn = false`, so it plays the flat design (`Realizer.mm:289-291`) through the 10 ms glide: gapless, with no silence gap, which is good for A/B. Compare is disabled when the EQ is Off or in Pure Mode (`EQAudibleState.swift:19-22, 41-43`).
- **Level matching is not live yet.**
  - `outputGainDb` is never written (`TargetState.h:23-24`), so "matched loudness" is not true on this branch. EQ1c's Realizer part and EQ2 are pending (`amendments.md:151`).
  - *After they land:*
    - each arm is matched to the source to ≤ 0.112 dB of integrated loudness, so two curves match each other to ≈ 0.22 dB at worst (`engine-plan.md:223-231`);
    - short-term (3 s) level still wanders p05–p95 −0.8…+0.9 dB (Warm), up to −2.9…+0.9 dB for a strong Tone (`engine-plan.md:259-262`);
    - level JNDs are 0.25–1 dB (`literature.md:156`), so short windows are near or above threshold.
- **Can it support "sounds better / not"?** Yes, as a base. The predictor gives −ΔL for *any* 31-point curve (`TrackLoudnessProfile.h:95-119`), so the arms can be "current vs suggestion", not just "curve vs Off". Changes needed (recommended first):
  1. Generalise Compare to *curve vs curve*: publish the alternative points instead of `isOn = false`.
  2. Make it **unlabelled and randomised**: "1 / 2". Hide the ghost curve during a trial. Today's UI shows which arm is which and draws the missing curve (`ui-plan.md:211-216`).
  3. **Replay the same excerpt** (e.g. the last 8–10 s) for each arm. Otherwise the music changes under the comparison, and the short-term wander above exceeds the JND.
  4. Hold **Intensity at 0** (P1: no normaliser) or freeze the normaliser during a trial, so its 1 dB/s adaptation can't differ between arms (`LoudnessModule.h:51`). Keep the limiter identical across arms; match by attenuating the louder arm (`literature.md:165`).
  5. Never in Pure Mode.

  Biases still uncontrolled: order and recency, the presentation being a hold rather than a fixed-duration switch, and adaptation over minutes. The RO6 / RO12 tracks should cover them.

---

## 3. Risks

1. **Licences.**
   - NC weights: Essentia models, MAEST, MERT, MuQ, madmom models, and SongFormer through MuQ.
   - AGPL code: Essentia, MAEST.
   - GPL: Matchering.

   All are fine for personal/OSS. They block a commercial release without negotiated licences; MTG offers a proprietary licence [D02]. The Essentia LICENSE file says NC-ND while the models page says NC-SA [D03]: ask MTG before relying on either.
2. **Objective hacking.** The one permissive "quality" model rewards unbounded treble [M06]. Any optimiser needs hard caps (±3 dB per region) and a prior: a target curve or reference.
3. **Bandwidth and mono blind spots.** Learned models cannot hear > 8–12 kHz or stereo width. Air suggestions must be DSP-driven.
4. **Catalogue bias.** Western taxonomies gave low-confidence labels on this library's Sri Lankan material [M02]. Theme steering by genre label may misfire.
5. **Shipping path.** Python cannot ship in the app. Convert to Core ML (coremltools) with static shapes, or embed onnxruntime. The ORT CoreML EP was 50× slower than its CPU EP with a dynamic batch [M02, D31]. WavLM, MERT and MuQ conversions are unproven: no public port was found (Q2, Q3, Q10).
6. **Prerequisites not yet built:** the Swift analyzer, the Realizer's −ΔL, EQ2, the Arbiter and the §11 clamps. Until they exist, an AI-EQ would play un-matched and unclamped beyond ±12.
7. **The hardware floor is untested.** Every timing is from an M4 Pro. The M1 Pro (LD-18, `architecture.md:31`) is untested (E: 2–4× slower).

---

## 4. Evidence table

`ID | RO(s) | type | claim | numbers | method / output | code + weights licence | limitation | grade | URL`

| ID | RO | Type | Claim | Numbers | Method / output | Licence | Limitation | Grade | URL |
|---|---|---|---|---|---|---|---|---|---|
| D01 | 8 | repo README | Essentia is AGPL-3.0; README lists Linux pip | — | library | AGPL-3.0 | README omits the macOS wheels PyPI has (D04) | C | https://github.com/MTG/essentia |
| D02 | 1, 8 | model docs | Essentia models CC BY-NC-SA 4.0, proprietary on request; Discogs-EffNet 400 styles; heads list; ONNX `discogs-effnet-bsdynamic-1.onnx` | 56 mood/theme, 87 genre, 40 instruments | CNN on 16 kHz mel | NC-SA | no decade or quality model | C | https://essentia.upf.edu/models.html |
| D03 | 8 | licence file | models LICENSE says "Attribution-NonCommercial-NoDerivatives 4.0", links BY-NC-SA | — | — | NC | internal inconsistency | C | https://essentia.upf.edu/models/LICENSE |
| D04 | 8 | registry | essentia-tensorflow 2.1b6.dev1389 has macOS arm64 wheels cp311–313 | 115.3 MB | PyPI JSON | AGPL | dev builds | C | https://pypi.org/pypi/essentia-tensorflow/json |
| D05 | 1, 2, 8 | repo README | Audiobox Aesthetics: 4 axes CE/CU/PC/PQ; pip package; checkpoint on HF/S3 | — | WavLM-based | CC-BY-4.0 (+MIT parts) | no timing or EQ info | C | https://github.com/facebookresearch/audiobox-aesthetics |
| D06 | 1, 2 | preprint | PQ covers clarity, dynamics, frequency balance, spatialisation; 16 kHz mono; 10 s windows; ≈500 h, ⅓ music | music PCC vs human OVL 0.464 (PAM-music); vs GT-PQ 0.587; AES-Natural music 0.887 | MOS-correlation | — | nothing on EQ sensitivity | B | https://arxiv.org/html/2502.05139v1 |
| D07 | 8 | model card / API | HF licence cc-by-4.0; checkpoint 415,520,834 B | 103.9 M params (counted, M) | — | CC-BY-4.0 | — | C | https://huggingface.co/facebook/audiobox-aesthetics |
| D08 | 1, 8 | repo README | LAION-CLAP code CC0-1.0; music checkpoints; 48 kHz | — | audio–text | CC0 | checkpoint licence not stated in README | C | https://github.com/LAION-AI/CLAP |
| D09 | 8 | model card | `lukewys/laion_clap` metadata cc0-1.0; music `.pt` 2.35 GB | — | — | CC0 | "use at your own risk" | C | https://huggingface.co/lukewys/laion_clap |
| D10 | 8 | model card | `laion/larger_clap_music` Apache-2.0, music-trained | 776 MB | HF transformers | Apache-2.0 | params not stated | C | https://huggingface.co/laion/larger_clap_music |
| D11 | 8 | repo README | MS-CLAP code MIT; versions 2022 / 2023 / clapcap | — | audio–text | MIT | — | C | https://github.com/microsoft/CLAP |
| D12 | 8 | model card | msclap weights MS-PL; 2023 = 690 MB | — | — | MS-PL | — | C | https://huggingface.co/microsoft/msclap |
| D13 | 1, 8 | model card | MERT-v1-95M: CC-BY-NC-4.0, 95 M, 24 kHz, 75 Hz, 5 s context | 20 k h training | SSL features | NC | — | C | https://huggingface.co/m-a-p/MERT-v1-95M |
| D14 | 1, 8 | repo README | MuQ code MIT, weights CC-BY-NC 4.0; ~300 M / ~700 M; 24 kHz only | — | SSL / music–text | MIT / NC | — | C | https://github.com/tencent-ailab/MuQ |
| D15 | 1, 8 | model card | MAEST-30s CC BY-NC-SA, 86.9 M params, 16 kHz | 347.5 MB (API) | transformer | NC-SA | — | C | https://huggingface.co/mtg-upf/discogs-maest-30s-pw-129e |
| D16 | 8 | repo README | MAEST code AGPL-3.0 | — | — | AGPL | — | C | https://github.com/palonso/MAEST |
| D17 | 1, 8 | repo README | All-In-One: MIT; 10 segment labels, beats, tempo; uses Demucs stems | 10 songs / 33 min in 73 s on an RTX 4090 | ensemble of 8 | MIT / weights U | GPU timing only | C | https://github.com/mir-aidj/all-in-one |
| D18 | 1, 8 | repo README | SongFormer: CC-BY-4.0 code; 8 labels; MuQ + MusicFM encoders; "2–4 s per song" on an L40 | 104.5 MB + 2.76 GB (API) | SSL + transformer | CC-BY-4.0 / weights unstated | author benchmark | C | https://github.com/aslp-lab/songformer |
| D19 | 1 | preprint (search summary only) | SongFormer SOTA on SongFormBench; SongFormDB > 10 k tracks | — | — | — | not opened | U | https://arxiv.org/html/2510.02797v2 |
| D20 | 1, 8 | repo README | madmom code BSD; models and data CC BY-NC-SA 4.0 | — | beats, tempo, key, chords | BSD / NC-SA | stale (2018 release, D28) | C | https://github.com/CPJKU/madmom |
| D21 | 1 | repo README | MSAF MIT | — | structure framework | MIT | algorithms not listed on the page | C | https://github.com/urinieto/msaf |
| D22 | 1, 5 | repo README | Matchering GPL-3.0: matches RMS, FR, peak and width to a reference | — | DSP | GPL-3.0 | no timing | C | https://github.com/sergree/matchering |
| D23 | 1, 8 | Apple docs | `SNClassifySoundRequest`: built-in v1 or a custom Core ML model; `knownClassifications` | macOS 10.15+ | — | Apple | — | C | https://developer.apple.com/documentation/soundanalysis/snclassifysoundrequest.md |
| D24 | 1, 5, 8 | Apple docs | `MLSoundClassifier` trains on ≥10 examples per class and exports a Core ML model for SoundAnalysis | macOS 10.15+ | — | Apple | feature extractor not named | C | https://developer.apple.com/documentation/createml/mlsoundclassifier.md |
| D25 | 1 | class map | YAMNet 521 classes, including 34 genre classes (indices 211–248) | — | — | Apache-2.0 (search, U) | Core ML port is 3rd-party (U) | C | https://raw.githubusercontent.com/tensorflow/models/master/research/audioset/yamnet/yamnet_class_map.csv |
| D26 | 1 | repo README | PANNs code MIT; weights on Zenodo; CNN14 mAP 0.431 | — | AudioSet tagger | MIT / U | — | C | https://github.com/qiuqiangkong/audioset_tagging_cnn |
| D27 | 1 | preprint | era recognition: decade 67.5 % exact / 91.7 % ±1, audio only (MSD); 78.8 % / 97.5 % with artist info | 85 k MSD tracks | contrastive CNN | not released | Western catalogue | B | https://arxiv.org/html/2407.05368v1 |
| D28 | 8 | registry | last releases: madmom 0.16.1 (2018-11), allin1 1.1.0 (2023-10), matchering 2.0.6 (2022-10), msaf 0.1.80 (2023-06), muq 0.1.0 (2024-12) | — | PyPI JSON | various | — | C | https://pypi.org/pypi/madmom/json |
| D29 | 1, 2 | peer-reviewed (ICASSP 2025) | OpenL3 / PANNs / CLAP embeddings move monotonically along one direction under gain, low-pass, reverb and bitcrush, but the displacement is high-dimensional and not linearisable | no numbers in the abstract | CCA | — | abstract only | B | https://arxiv.org/abs/2501.15900 |
| D30 | 3 | conference + preprint | blind EQ from a pretrained semantic-embedding backbone with a light head; subjective tests ≈ an oracle | no numbers on the abstract page | — | not released | abstract only; date inconsistency | B | https://arxiv.org/abs/2607.23846 |
| D31 | 8 | vendor docs | ORT CoreML EP: "performance may be negatively impacted by inputs with dynamic shapes"; `RequireStaticInputShapes` | — | — | MIT | — | C | https://onnxruntime.ai/docs/execution-providers/CoreML-ExecutionProvider.html |
| M01–M06 | 1, 2, 8 | own measurement | see §2 RO8-1 / RO8-2 | n = 3 clips; 9 windows | scripts in `scratchpad/bench-scripts/` | — | 3 clips, one machine, no listeners | M | `scratchpad/bench-results/` |

---

## 5. Search log

All searches and fetches were run on 2026-10-10.

| # | Query or fetch | Source | Screened | Included |
|---|---|---|---|---|
| Q1 | music structure analysis model 2025 verse chorus boundary detection open source SongFormer | web | 18 | 1 (D18; D19 as U) |
| Q2 | Audiobox Aesthetics Core ML OR ONNX OR MLX conversion | web | 9 | 0 |
| Q3 | MERT music model MLX OR "Core ML" Apple Silicon inference | web | 9 | 0 |
| Q4 | Apple SoundAnalysis SNClassifierIdentifier version1 sound classes list music | web | 9 | 1 (D23) + M01 |
| Q5 | Essentia TensorflowPredictEffnetDiscogs inference speed CPU real-time factor | web | 9 | 0 (no published RTF, so measured: M02) |
| Q6 | estimating release year decade of music recordings from audio deep learning production era | web | 10 | 1 (D27) |
| Q7 | YAMNet license Apache 2.0 AudioSet 521 classes music genre Core ML | web | 9 | 1 (D25) |
| Q8 | Dolby Audio intelligent equalizer volume leveler processing order white paper | web | 9 | 0 (Dolby PDF unreadable; patent chain only from a snippet, U) |
| Q9 | sensitivity of pretrained audio embeddings to equalization spectral tilt robustness music representation | web | 9 | 2 (D29, D30) |
| Q10 | WavLM coremltools conversion Core ML Neural Engine speech model | web | 10 | 0 |
| Q11 | onnxruntime CoreMLExecutionProvider dynamic input shape slow recompile | web | 9 | 1 (D31) |
| Q12 | automatic equalization music player maximum boost safety limit adaptive EQ architecture limiter loudness normalization | web | 10 | 0 (patents and forums; not opened) |
| R1 | PyPI JSON: essentia, essentia-tensorflow, audiobox_aesthetics, madmom, allin1, matchering, msaf, laion-clap, msclap, muq | PyPI | 10 | 10 (D04, D28) |
| R2 | HF API: audiobox-aesthetics, msclap, larger_clap_music, MERT-v1-95M, MuQ-large-msd-iter, MAEST-30s, SongFormer | HF | 7 | 7 |
| F | direct fetches of every URL in §4 (READMEs, model cards, LICENSE files, Apple docs, arXiv pages) | primary | 27 | 27 |

**Saturation.**
- *RO8 conversion paths:* Q2, Q3 and Q10 in a row found no public Core ML or MLX port of Audiobox, MERT or WavLM, so I stopped there (saturated).
- *RO1 structure tools:* stopped at the cap. SongFormer was the only new tool found after the brief's list.
- *Snowballing:* partial. SongFormer → MuQ / MusicFM (its dependencies). Deng 2025 → Moliner 2026, found in the same result set. The Audiobox paper's PAM baseline was not followed.

---

## 6. Answers per RO

| RO | Answer (recommendation first) | Confidence | Key IDs |
|---|---|---|---|
| **RO8-a: compute** | Feasible. Fast-tier analysis (DSP profile + EffNet + Audiobox) costs < 2–3 s per track on an M4 Pro, so analyse current + next at track start, and the library in the background on AC power. Defer structure models (All-In-One / SongFormer): use DSP novelty boundaries first. | High (M4 Pro); med (M1 Pro) | M01, M02, M04, D17, D18 |
| **RO8-b: licences** | For personal/OSS: Audiobox (CC-BY), CLAP (CC0 / Apache), YAMNet, Apple and in-repo DSP are clean. Essentia / MAEST / MERT / MuQ / madmom weights are NC, and Essentia / MAEST code is AGPL. Prefer the permissive set now, so a future commercial path stays open. If Essentia is used, ship ONNX weights through onnxruntime rather than the AGPL library, and amend ADR-005. | High | D01–D03, D05–D16, D20, D22 |
| **RO8-c: hooks** | Feed the suggestion through the existing one dispatch, as a separate bounded layer. Add a glide hint (≤ 2 s τ) to `EqIntent`. Reuse the profile for section-local −ΔL. Cache features in a new LibraryStore table (v8) and keep feedback as durable user data. | High (hooks); med (design) | repo citations in RO8-3 |
| **RO8-d: fair A/B** | Yes, after EQ1c (Realizer −ΔL) and EQ2 land, with curve-vs-curve, blind labels, a replayed excerpt and Intensity 0 or a frozen normaliser. Not today: the gain is never applied. | Med | RO8-4 citations; `literature.md:156-166` |
| **RO1 (tools)** | Spectral balance over time comes from the in-repo profiler, not ML (learned heads are insensitive). Genre and mood come from EffNet or CLAP, but with low confidence on this library's material. Structure needs a heavy model or DSP novelty. Era: tag + DSP proxies. | Med | M02, M03, D25, D27, D29 |
| **RO7 (architecture)** | EQ/Tone authority only. Loudness-neutral via −ΔL; ±3 dB per region; subject to the limiter ceilings. Never in Pure Mode, never switches the EQ on, never touches the normaliser, limiter, Intensity, crossfeed or device. Under the future Arbiter, a "content-adaptive" contributor that can't override user-locked directions. | Med | `architecture.md:161-171, 267, 273-287`; `amendments.md:18-36, 59`; `DSPKernel.cpp:132-152` |
| **RO2 (probe input only)** | Audiobox PQ is not a usable EQ objective: monotone in treble, scoops presence. At most a paired "harshness alarm" on older recordings. | Med (3 clips) | M05, M06, D06 |

## 7. Gaps

1. No listener data: does any automatic score track the founder's "better / not" on the same track? (RO2 / RO12)
2. M1 Pro timings, Core ML conversions (Audiobox / WavLM, EffNet static shape) and ANE use are unmeasured.
3. CLAP / MuQ-MuLan zero-shot "theme" prompts were not benchmarked: model sizes 0.7–2.4 GB were left out of this pass.
4. Structure models were not run on a Mac (All-In-One / SongFormer). Their weight licences are unstated.
5. The probe used 3 clips, and none is a modern commercial master. Sensitivity on loud modern pop and on lossy sources is unknown.
6. Section-local −ΔL and a ≥ 1 s S2 glide are designed here, not tested. Swell and loudness behaviour at τ > 160 ms is unmeasured in the repo's tdsim.
7. The MTG licence inconsistency (NC-SA vs NC-ND) is unresolved.

**Artifacts (scratchpad).**
- Scripts: `bench-scripts/aes_eq_probe.py`, `aes_eq_sweep.py`, `aes_timing.py`, `effnet_bench.py`, `effnet_timbre_probe.py`, `sa_probe.swift`.
- Results: `bench-results/aes_eq_probe.json`, `aes_summary.txt`, `aes_sweep.txt`, `effnet.txt`, `effnet_timbre.txt`.
- Downloads were kept in `bench-models/` (Essentia, 45 MB) and `abx-models/` (Audiobox, 415 MB). The venvs are `bench-venv/` and `abx-venv/`.
