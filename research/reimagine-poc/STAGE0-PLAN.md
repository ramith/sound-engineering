# Stage-0 Experiment — Executable Plan (research-enriched)

**Goal:** answer the one make-or-break question for the Level-2 pivot — *does ACE-Step produce a musically coherent modern backing from a real (Sinhala) vocal?* — before building any pipeline.
**Target machine (verified):** Apple **M4 Pro, 24 GB** unified memory, macOS 26.5, `uv` + `ffmpeg` installed, ~290 GB free.
**Status:** plan only — awaiting green light to execute Phase 0.
**Companion:** `REPORT.md` (landscape + Level-2 decision).

---

## TL;DR — the chain + the non-obvious gotchas

```
old_track →[isolate] Mel-Band RoFormer →[restore] Smule Renaissance →[generate] ACE-Step 1.5 "Complete" →[rough-mix] → listen
            (audio-separator)            (identity-safe)              (0.6B LM, base DiT, MLX)        (level-match)
```

**The four gotchas that will bite if ignored:**
1. **ACE-Step default OOMs on 24 GB.** The shipped macOS script loads the **1.7B LM** (~42 GiB peak → crash). Use the **0.6B LM**. Set `PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0` and `PYTORCH_ENABLE_MPS_FALLBACK=1`; launch with `--torch_compile False`.
2. **Three separate venvs** — `audio-separator` pins `torch<2.5`, ACE-Step wants `torch≥2.9`, Smule wants latest. They cannot share an env.
3. **Generation is slow** (~20–35 min for a 3-min song at 60 steps; no M4-Pro benchmark). **Test a 30–60 s vocal excerpt first.**
4. **Non-Western bias is the real risk** (documented: models Westernize non-Western material). This *is* what Stage-0 tests. Mitigate with explicit Sinhala-instrument prompts + reference-audio conditioning.

Everything is open-weights + Mac-runnable. ACE-Step / HTDemucs are Apache-2.0/MIT; verify the RoFormer checkpoint's license (fine for personal research).

---

## Phase 0 — environment & tooling

Work in `research/reimagine-poc/`. Three venvs (all Python 3.12):

**0a. Vocal isolation env**
```bash
uv venv .venv-sep --python 3.12 && source .venv-sep/bin/activate
uv pip install "audio-separator[cpu]"   # ONNX + MPS PyTorch path; do NOT use [gpu] on Mac
deactivate
```

**0b. Vocal restoration env**
```bash
uv venv .venv-restore --python 3.12 && source .venv-restore/bin/activate
git clone https://github.com/smulelabs/smule-renaissance vendor/smule-renaissance
uv pip install torch torchaudio && uv pip install -r vendor/smule-renaissance/requirements.txt
deactivate   # checkpoint (smulelabs/Smule-Renaissance-Small, ~42 MB) auto-downloads on first run
```

**0c. ACE-Step 1.5** (already cloned to `vendor/ACE-Step-1.5`)
```bash
cd vendor/ACE-Step-1.5 && uv sync     # installs mlx + torch≥2.9 into its own .venv (Python 3.11–3.12)
# Models auto-download on first run to ~/.cache: base DiT (~7 GB) + 0.6B LM (~1.2 GB) ≈ ~8.5 GB
```

**0d. Pick the test material:** the Sinhala track (`Seetha Kandu Yaye`). **Cut a 30–60 s excerpt** of a representative section (verse + a bit of chorus) for the first generation pass.

---

## Phase 1 — isolate + restore the vocal (fast, local)

```bash
# Isolate vocal (Mel-Band RoFormer ~11.4 dB SDR; cleaner than htdemucs ~8 dB)
source .venv-sep/bin/activate
audio-separator "data/seetha_excerpt.wav" \
  --model_filename model_mel_band_roformer_ep_3005_sdr_11.4360.ckpt \
  --output_dir ./out/stems --output_format WAV
deactivate
# → out/stems/..._(Vocals)_....wav

# Restore the isolated vocal (identity-preserving; discriminative, no hallucination)
source .venv-restore/bin/activate
python vendor/smule-renaissance/main.py "out/stems/<vocals>.wav" -o "out/vocals_restored.wav"
deactivate
# Smule outputs 48 kHz → resample to 44.1 kHz for ACE-Step:
ffmpeg -y -i out/vocals_restored.wav -ar 44100 out/vocals_restored_44k.wav
```
**Check by ear / spectrogram:** vocal cleanly isolated (low bleed)? identity intact after restore? (A/B raw stem vs restored.)

*License-clean fallback for isolation:* HTDemucs (MIT, MLX) — `uvx demucs --two-stems vocals <file>` — if the RoFormer checkpoint's license is a concern.

---

## Phase 2 — generate the backing (the make-or-break)

```bash
cd vendor/ACE-Step-1.5
export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0
export PYTORCH_ENABLE_MPS_FALLBACK=1

# Gradio UI (simplest for a manual Stage-0):
uv run acestep --lm_model_path acestep-5Hz-lm-0.6B --torch_compile False
# → http://127.0.0.1:7860 → Generation Mode: "Complete" (base model only)
#   → upload Source Audio = out/vocals_restored_44k.wav
#   → select Track Names to add (drums/bass/guitar/etc.) → Caption (style) → Generate
```
- **Settings:** 60 steps (ODE/Euler), CFG ≈ 7.0, duration = excerpt length. (Drop to 30 steps for fast iteration.)
- **Caption — lean into the genre to fight Westernization.** Try ≥3 variants, e.g.:
  - `"traditional Sri Lankan folk, sitar, tabla, harmonium, dholak, gentle percussion, minor scale, warm"`
  - `"acoustic folk ballad, nylon guitar, soft hand percussion, strings, intimate"`
  - `"modern cinematic folk-pop, live drums, bass, tasteful synth pads"`
- **Scriptable alternative:** `uv run acestep-api --lm_model_path acestep-5Hz-lm-0.6B --torch_compile False --port 8000`, then POST the vocal + caption. *(Confirm exact endpoint/field names against `docs/en/API.md` in the clone — the field schema below is provisional.)*
- **Time the first 30 s run** to calibrate expectations before doing longer takes.

Expected behavior: ACE-Step conditions on the vocal's *style* (speaker embedding over ~10 s windows), not strict melody — so a harmonically-coherent-but-not-beat-locked backing is **success** for Stage-0 (DTW alignment is deferred).

---

## Phase 3 — rough mix, listen, decide

Level-match only (no DTW, no limiter — just enough to judge): mix `vocals_restored_44k.wav` + each backing, vocal ≈ −16 LUFS, backing ≈ −20 LUFS, mono-sum polarity check, hard-clip guard → `out/stage0_mix_<take>.wav`. (Small `scripts/rough_mix.py`, numpy+soundfile+ffmpeg.)

**You judge** (the founder's ear is the verdict):
- **Harmonic fit** — does the backing sit in the vocal's key/changes?
- **Rough tempo** — roughly aligned (ignore fine rubato)?
- **Style** — idiomatic for the genre, or Westernized/clashing?

**Decision:**
- **GO** — coherent on ≥1 prompt → Level 2 is real; build the full pipeline (alignment + C++-kernel mix/master).
- **PARTIAL** — works for some styles/prompts → note what helps; narrow scope.
- **NO-GO** — incoherent/Westernized across prompts → ACE-Step needs Sinhala fine-tuning (NVIDIA + data) or a different generator; revisit.

---

## Fallbacks if ACE-Step underwhelms (in order)

1. **Vary the prompt first** (3–5×, explicit Sri Lankan instruments) — ACE-Step is text-heavy; this often fixes "Westernized."
2. **MusicGen-Melody** (MLX port) — stronger *melody* conditioning; **CC-BY-NC weights → research only**, ~30 s segments (stitch).
3. **DiffRhythm 2** (Apache-2.0) — text-only full-song; use as a from-scratch backing to align under the vocal.
4. **YuE** (Apache-2.0) — full-song; more Level-4 than Level-2.
5. *(SingSong — ideal task fit but still no open weights; skip.)*

---

## Risks / expectations (from the research)

| Risk | Likelihood | Mitigation |
|---|---|---|
| Westernized/clashing backing on Sinhala material | **High** (documented bias; unvalidated task) | explicit instrument prompts; reference-audio cond.; this is the thing Stage-0 measures |
| OOM on 24 GB | High if mis-configured | 0.6B LM, MPS watermark=0.0, `--torch_compile False` |
| Slow generation | Medium | 30–60 s excerpt first; 30 steps for iteration |
| Grid-locked groove / loose vocal sync | Medium | acceptable for Stage-0; DTW align in full POC |
| Vocal bleed corrupts conditioning | Low–Med | Mel-Band RoFormer (high SDR) + Smule restore |

## Deliverable
`research/reimagine-poc/STAGE0-FINDINGS.md` — what ran, generation times on M4 Pro, the rendered takes in `out/`, and the **GO / PARTIAL / NO-GO** verdict with your ear notes. Plus the small scaffold scripts so it's repeatable.

## Flagged uncertainties
Exact ACE-Step API field names (verify vs `docs/en/API.md`); exact base-DiT param size/name (2B vs 3.5B — confirm at download); M4-Pro generation time (only M1/M2 numbers public); RoFormer checkpoint license (verify; HTDemucs is the MIT fallback).
