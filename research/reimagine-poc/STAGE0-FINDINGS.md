# Stage-0 Findings — does ACE-Step produce a coherent backing for a Sinhala vocal?

**Date:** 2026-06-25 · **Machine:** Apple M4 Pro, 24 GB, macOS 26.5 · **Companion:** `STAGE0-PLAN.md`, `REPORT.md`

**Make-or-break question (from the plan):** *Can ACE-Step 1.5 (Western-trained, open weights) generate a musically coherent modern backing from a real Sinhala vocal, on this Mac, self-hosted?*

---

## ⏱️ OUTCOME (2026-06-26) — read this first

**Verdict: NO-GO on the generation step as configured — but the cause is now isolated, and the voice pipeline is a clear WIN.**

- **Voice isolate + restore: excellent.** Founder's pick from the whole experiment is the **raw** full-song restored vocal (`out/seetha_full_vocals_restored.wav`) — Mel-Band RoFormer → Smule Renaissance, *no* added EQ/air/loudness. (Minimal processing preferred; see the rest of this doc / project memory.)
- **ACE-Step "Complete" backing: garbled mush, confirmed by ear.** Systematically ruled out: vocal prep (great), corrupt weights (base DiT + VAE SHA256-verified), stale version (latest v0.1.8), settings (40–60 steps / CFG 7 / euler), **planner size (0.6B *and* 1.7B both fail)**, **DiT backend (MLX *and* PyTorch both fail)**, and `thinking` on/off. Beat-salience: real song ≈ 0.22, base outputs 0.017–0.08 (incoherent).
- **Root cause = the `acestep-v15-base` checkpoint specifically.** Diagnostic: **`acestep-v15-turbo` generates clean, rhythmic music on the same machine** (beat-salience **0.464**, clear harmonic+beat spectrogram). So the Mac / MLX / memory / install all work — only base malfunctions. **But base is the *only* DiT that supports "Complete" (vocal→backing); turbo/sft/turbo-rl cannot.** So turbo can't be a drop-in for our task.
- **Open paths:** (1) **turbo workflow** — turbo text2music backing (key/tempo-matched) + align under the real vocal (keeps local, "Very High" quality, more manual); (2) **cloud GPU** — run base+Complete on CUDA (validated path) to test if the base bug is Apple-Silicon-specific; (3) **investigate the base bug** (fails on both engines here — unusual; check upstream issues / a different base revision).

*Everything below is the original 2026-06-25 write-up from the first generation pass (kept for the record).*

---

## TL;DR — the pipeline ran end-to-end, locally, and produced three listenable takes

```
Seetha Kandu Yaye (45s excerpt, 0:30–1:15)
  →[isolate]  Mel-Band RoFormer (audio-separator)        → vocal stem
  →[restore]  Smule Renaissance Small (identity-safe)     → out/vocals_restored_44k.wav
  →[generate] ACE-Step 1.5 "Complete" (base DiT, 0.6B LM, MLX)  → 3 backings (folk / acoustic / modern)
  →[rough-mix] level-match vocal −16 LUFS over backing −20 LUFS → out/stage0_mix_<tag>.wav
```

Everything ran on-device, open-weights, no SaaS. **Your ear is the verdict** — see *Listen* below.

---

## What ran, and the key unblock

The blocker that paused this experiment was a `500` on `POST /release_task`. Root cause: **multipart form-data coerces every field to a string**, and the server does an integer comparison on numeric params → `'<' not supported between instances of 'str' and 'int'`. 

**Fix:** send a **JSON** body (preserves typed ints/floats) and reference the vocal by **`src_audio_path`** (absolute, server-local) instead of a multipart file upload. With that, Complete mode runs clean. (`scripts/generate_backing.py` now does this; the server is launched via Gradio `acestep --config_path acestep-v15-base --enable-api` so the **base** DiT is the default model — Complete mode needs base, not turbo.)

**Settings:** base DiT, 0.6B LM, `thinking=true`, **40 inference steps**, CFG 7.0, duration 45 s, batch 1, MLX backend.

## Verification (so the listen is trustworthy)

- **Complete output is accompaniment-only** — separating a backing gives a Vocals stem at **−79 dBFS** (silence) vs Instrumental at −14.9 dBFS. ACE-Step did **not** regenerate a vocal → the **Level-2 constraint holds** (the real vocal is never synthesized), and mixing the original vocal back in is the correct evaluation.
- **Mixes are clean** — RMS ≈ −18 dBFS, peaks −2 to −3.5 dBFS, no clipping (limiter at 0.97).

## Generation performance (the pleasant surprise)

**~50 s per 45-second take at 40 steps** on the M4 Pro via MLX — the plan budgeted 7–12 min. That is **~10–15× faster than expected**, which makes iterating on prompts/seeds cheap and changes the cost calculus for the full pipeline.

## What ACE-Step's "songwriter" planned per take

| Take | Prompt (style caption) | Key | BPM | Time sig | Seed |
|---|---|---|---|---|---|
| **folk** | traditional Sri Lankan folk, sitar, tabla, harmonium, dholak, gentle percussion, minor scale, warm | D minor | 158 | 4/4 | 475077365 |
| **acoustic** | acoustic folk ballad, nylon guitar, soft hand percussion, warm strings, intimate, organic | C major | 100 | 3/4 | 4270583283 |
| **modern** | modern cinematic folk-pop, live drums, electric bass, tasteful synth pads, lush, polished | D major | 107 | 4/4 | 1064183223 |

**Westernization signals to listen for (this is the experiment's whole point):**
- **`vocal_language` came back `unknown` for all three** — the model never identified the vocal as Sinhala. It conditions on the vocal's *style embedding*, not its language/scale.
- **Each take chose a different key, picked independently of the vocal** (D minor / C major / D major) and one chose **3/4**. Complete mode does **not** strictly lock to the vocal's pitch centre or metre → **harmonic/tempo fit is the gamble**, and is exactly what your ears need to judge.

---

## Deliverables (in `out/`)

| File | What it is |
|---|---|
| `out/vocals_restored_44k.wav` | the restored Sinhala vocal (reference / dry) |
| `out/backing/backing_{folk,acoustic,modern}_0.wav` | the three bare generated backings (no vocal) |
| `out/stage0_mix_{folk,acoustic,modern}_0.wav` | **← listen to these:** vocal level-matched over each backing |

Repeatable via `scripts/run_stage0_backings.sh` (generate) + `scripts/rough_mix.sh` (mix).

---

## Listen — and the GO / PARTIAL / NO-GO call (your ear)

Play the three `stage0_mix_*.wav`. For each, judge:
1. **Harmonic fit** — does the backing sit in the vocal's key / chord changes, or clash?
2. **Tempo/feel** — roughly aligned (ignore fine rubato), or fighting the vocal?
3. **Style** — idiomatic for the genre, or generically Westernized / wrong-instrument?

> **Verdict:** _(to fill in after listening)_
>
> - **GO** — coherent on ≥1 take → Level 2 is real; build the full pipeline (DTW alignment + C++-kernel mix/master).
> - **PARTIAL** — works for some styles → note which prompts help; narrow scope.
> - **NO-GO** — incoherent / Westernized across all → ACE-Step needs Sinhala fine-tuning or a different generator (see `STAGE0-PLAN.md` fallbacks).

## If results underwhelm — cheap next moves (now that generation is ~50 s)
1. **More prompt/seed variants** — generation is cheap; sweep 5–10 captions emphasising specific Sri Lankan instruments and "minor scale / raga-like".
2. **Bump steps to 60–80** for the most promising prompt (still ~1–2 min).
3. **Reference-audio conditioning** — feed a Sinhala-genre reference track to pull the style off the Western default.
4. Only if all fail: revisit generator choice / fine-tuning (the larger, slower path).
