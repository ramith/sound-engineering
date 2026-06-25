# Generative Music "Re-Imagination" — Landscape & Feasibility Report

**Status:** Research landscape / decision brief (no code yet — Stage-0 POC will live in this folder) · **Date:** 2026-06-20
**Method:** Two parallel deep-research agents — `scientific-literature-researcher` (open-weights model landscape, licensing, rights) + `audio-dsp-agent` (Apple-Silicon self-host feasibility + Level-2 architecture).
**Constraint (hard):** **self-hosted on Apple Silicon (Mac Studio class), open weights only** — no SaaS (Suno/Udio/commercial API).

> Companion to `research/legacy-remaster-poc/` (the classical-remaster spike that motivated this pivot).

---

## 0. Why this pivot

Empirically established by the remaster spike (the metallic-BWE saga): **classical remastering cannot make a 30-year-old recording "vivid."** The missing 8–22 kHz is genuinely absent, not hidden; synthesizing it from the presence band's harmonics sounds metallic at any audible level. To get vividness you must **generate** — depart from the original signal. That's a shift from **restoration** (fidelity-first) to **re-creation** (generative).

---

## 1. The four levels of re-imagination

| Level | Keeps | Regenerates | "Still the song?" | Open + self-hostable? |
|---|---|---|---|---|
| **1. Generative restoration** | whole performance | only fidelity/detail (learned, not DSP) | Yes — same take, filled in | ✅ (Apollo, FlashSR; AudioSR slower) |
| **2. Keep voice, re-produce backing** | the **vocal** (identity) | the instrumental backing | Mostly — same singer & song, modern production | ✅ **fully Apache-2.0/MIT chain exists** |
| **3. Re-perform from transcription** | composition (notes/lyrics) | everything sonic | Same composition, MIDI-cover feel | ✅ but **too lossy** as a primary path |
| **4. Full generative cover** | melody/lyrics as a prompt | the entire rendition | An AI cover | ✅ (YuE, ACE-Step, Apache-2.0) but over-reach |

**Recommendation: Level 2.**

---

## 2. Why Level 2 wins

1. **Never regenerate the voice — keep the recorded vocal, restore only.** Two independent reasons:
   - *Perceptual:* Singing Voice Conversion Challenge 2025 found **no system reached target-singer similarity** — open voice models land in the uncanny valley. (arXiv:2509.15629)
   - *Legal:* **ELVIS Act** (TN, Jul 2024), ~12 US states, pending **NO FAKES Act** criminalize AI voice mimicry. Keeping the *real* recorded vocal sidesteps the liability.
   - → the vocal sub-pipeline is **restorative** (separate → denoise/dereverb → light HF restore), never identity-altering generation.
2. **AI re-imagines only what it's good at** — dated drums/synths/space/image — while the irreplaceable human performance is preserved.
3. **Clean license path** (only level where the whole chain is commercial-OK): see §3.
4. **Delivers the actual want** ("make the beloved track feel vivid/modern") better than L1 (a plausible-but-invented fuller version of the *same* old backing), without L3's MIDI-cover losses or L4's "wholly new song."

---

## 3. The open-weights, self-hostable Level-2 stack

| Stage | Model | License | Apple-Silicon reality |
|---|---|---|---|
| Separate vocal | **HTDemucs 6s** (MLX) | **MIT** | ✅ ~12 s / 7-min song (~35× RT); already in the project |
| Restore vocal (identity-safe) | **Smule Renaissance Small** (10.4 M, discriminative) | **MIT** | ✅ seconds / 3-min vocal; *preferred over AudioSR* (no diffusion hallucination) |
| Analysis (tempo/key/melody/lyrics) | madmom·BeatFM / Chordino / Basic-Pitch / Whisper | MIT/open | ✅ seconds |
| **Generate backing from the vocal** | **ACE-Step 1.5** (2B DiT; vocal-conditioned accompaniment) | **Apache-2.0** | ⚠️ **15–25 min / 4-min track on M3 Ultra** — the workflow bottleneck |
| Align backing to vocal | DTW + Rubber Band time-warp | LGPL/GPL | ✅ seconds |
| Re-mix + master | existing **C++ DSP kernel** | project | ✅ real-time |

**License (the killer filter):** ACE-Step / YuE / HTDemucs are **Apache-2.0/MIT (commercial-OK)**. **Avoid** MusicGen-melody / JASCO / Stable Audio Open for the generative step — their *weights* are **CC-non-commercial**. SingSong (Google) is the conceptually perfect "vocals→accompaniment" model but has **no official open weights** → ACE-Step's `singing2accompaniment` is the practical open substitute.

---

## 4. Level-2 pipeline & the hard seams

```
old_track → [1] HTDemucs separate → vocal stem
          → [2] analyze vocal: tempo-map (madmom/BeatFM), key/chords, melody (Basic-Pitch), lyrics (Whisper), LUFS
          → [3] restore vocal: Smule Renaissance Small (+ conservative BWE if rolloff) — identity untouched
          → [4] ACE-Step: generate backing conditioned on (512-d vocal embedding + bpm + key + style prompt)
          → [5] align: DTW-warp backing beats onto the vocal's beat map (Rubber Band)
          → [6] recombine + master in the C++ kernel (polarity, level-match, BRIR, true-peak)
          → reimagined.wav
```

**Hard seams (ordered by difficulty):**
1. **Rubato / drifting-tempo alignment (hardest).** No click in old recordings; vocals drift. Beat-track the isolated vocal (unreliable without drums), condition ACE-Step at median BPM, DTW-warp the backing onto the vocal's beats. Target < 20 ms error on steady sections; sparse-rubato → phrase-boundary fallback.
2. **Conditioning on the vocal.** ACE-Step's speaker/style encoder embeds a 10-s vocal clip (avg 2–3) → biases *style/texture*, not strict melody. Add a Basic-Pitch melody hint if coupling is weak.
3. **The vocal's own dated fidelity.** Demucs vocal SDR ~8–10 dB (~30% bleed); often band-limited 5–8 kHz. Restore with **Smule Renaissance Small** (safe), *not* AudioSR (diffusion may hallucinate formants → identity drift, worse on non-Western voices). Accept residual bleed (masked by the new backing).
4. **Recombination.** Polarity check (invert backing if mono-sum drops); level-match (backing −20 LUFS, vocal −16 LUFS); high-pass vocal ~80–100 Hz to avoid bass comb-filtering.

---

## 5. Compute reality (M3 Ultra, 192 GB)

Unified memory (no PCIe transfer) → Mac is strong on **memory-bandwidth-bound** inference (autoregressive, separation), weak on **compute-bound** diffusion DiT. Everything is fast **except the generator**: HTDemucs ~12 s, Smule Renaissance seconds, analysis seconds — but **ACE-Step 1.5 is ~15–25 min / 4-min track** (extrapolated from RTX 3060/4090: 8–12 / 3–5 min; no published Mac benchmark). Workflow bottleneck for iteration (10 takes ≈ 2.5–4 h), not a capability blocker. A rented A100 (~$1/h) for the generation step only is the pragmatic escape.

---

## 6. Reuse from the existing project

- **HTDemucs stem engine** (Phase-1.5) → direct reuse.
- **C++ DSP kernel** → recombination/master stage (right boundary: generative in Python, final mix/master native).
- **Classical BWE + log-MMSE** (the remaster POC) → reusable vocal-restoration sub-step.
- **MLX/Core ML infra** → separation runtime (ACE-Step's DiT is PyTorch-MPS, separate path).

---

## 7. The de-risking FIRST experiment (Stage 0 — before any pipeline code)

**The one unknown that can invalidate the approach:** does ACE-Step produce a *musically coherent backing from a real Sinhala vocal stem*? (Training is overwhelmingly Western.) ~30 min:

```
1. htdemucs_6s separate the test track → vocal stem   (already in project)
2. Smule Renaissance Small on the vocal stem
3. ACE-Step 1.5 singing2accompaniment: vocal stem + "Sinhala folk song, acoustic, gentle percussion"
4. Listen: does the backing fit harmonically? does tempo roughly match? is the style plausible?
```
If no → Level 2 needs ACE-Step fine-tuning on Sinhala music (NVIDIA + data) or a different generator. Cheapest way to learn the make-or-break fact.

---

## 8. Riskiest unknowns (ordered)

1. **ACE-Step style coherence on non-Western (Sinhala) material** — highest; the Stage-0 experiment targets it.
2. **Beat tracking on isolated, rubato vocal stems** — DTW fails without reliable beats; phrase-boundary fallback.
3. **Generation time on Apple Silicon** — workflow risk (15–25 min/take), not correctness.
4. **Long-song coherence** — ACE-Step ≤ ~4:45; longer → segmented generation + crossfade.
5. **Demucs vocal bleed** — audible against a clean new backing; gentle transient suppression helps.

No Apple-Silicon benchmarks exist for ACE-Step/YuE/RoFormer — *benchmark before committing*.

---

## 9. Decision & next step

**Pursue Level 2.** The only level that is simultaneously (a) fully open/Apache-2.0/MIT, (b) self-hostable on a Mac, (c) free of uncanny-voice and voice-likeness-legal problems, and (d) a genuine answer to "make *this beloved track* feel vivid."

**Next:** run the **Stage-0 experiment** to settle genre coherence before investing in the pipeline. Then build the POC here (Python orchestration + the existing C++ kernel for the final mix/master), in the established build-and-verify pattern.

---

## References

Apollo (arXiv:2409.08514) · ACE-Step (arXiv:2506.00045; ACE-Step-v1-3.5B, Apache-2.0) · Smule Renaissance Small (arXiv:2510.21659, MIT) · HTDemucs (facebookresearch/demucs, MIT) · BS/Mel-Band RoFormer (arXiv:2310.01809) · SingSong (arXiv:2301.12662, no open weights) · MusicGen (CC-BY-NC weights) · JASCO (arXiv:2406.10970, NC) · Stable Audio Open (NC) · YuE (arXiv:2503.08638, Apache-2.0) · MT3 (arXiv:2111.03017) · basic-pitch (Apache-2.0) · SVCC-2025 (arXiv:2509.15629) · ELVIS Act.
