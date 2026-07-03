# Legacy-Remaster POC

A research POC for **on-the-fly "remastering" of old recordings** — make beloved but dated
tracks sound closer to a modern production: extend the rolled-off bandwidth, de-hiss, match
the tonal balance to a modern reference, normalize loudness, and widen the stereo image.

> Background, literature, and architecture rationale:
> [`docs/session-notes/legacy-remaster-research-spike.md`](../../docs/session-notes/legacy-remaster-research-spike.md).
> **Scope:** exploratory spike (LD-11 restoration territory) — not a committed Adaptive Sound feature.

The headline finding from the research: for legacy material, **bandwidth extension** (the missing
"air" above ~8 kHz and the missing deep bass) matters more than hiss. This POC implements the
*faithful, no-hallucination* layers in pure NumPy/SciPy so the whole chain runs far faster than
real-time, and ships an honest **bake-off harness** to compare the classical bandwidth-extension
baseline against learned models (AERO, FlashSR) when their weights are wired up.

## Quick start

```bash
cd research/legacy-remaster-poc
python3 -m venv .venv && source .venv/bin/activate
pip install -e .            # add '[dev]' for tests/ruff, '[ml]' for the learned BWE runners

# the UX you want: remaster a track and play it
legacy-remaster path/to/old_song.m4a

# match the tone to a modern track you like, and keep the output
legacy-remaster path/to/old_song.mp3 --reference path/to/modern.flac --keep out/remastered.wav
```

A bare path defaults to `play` — it remasters (the processing time is the "startup latency")
then plays via macOS `afplay` (or `ffplay`). Input can be **wav/flac/ogg/mp3** (libsndfile) or
**m4a/aac/mp4** (decoded via ffmpeg/afconvert). Output is WAV.

## Commands

| Command | What it does |
|---|---|
| `legacy-remaster PATH` | remaster `PATH` and play it (bare path ⇒ `play`) |
| `legacy-remaster play PATH [--keep OUT] [--no-play]` | remaster and play; optionally save |
| `legacy-remaster remaster PATH [-o OUT] [--plots DIR]` | remaster to a WAV + verification plots |
| `legacy-remaster make-test OUTDIR` | synthesize `modern_reference.wav` + `legacy_degraded.wav` |
| `legacy-remaster bakeoff PATH [--out DIR]` | compare bandwidth-extension methods (HF gain, RTF, musical-noise) |
| `legacy-remaster sim --rtf R --headstart H --duration D` | process-ahead buffer simulation |

Useful flags (shared by `play`/`remaster`): `--reference`, `--target-lufs -14`, `--ceiling -1`,
`--width 0.4`, `--rolloff HZ`, `--noise-start S --noise-dur D`, and `--no-dehiss / --no-bwe /
--no-match-eq / --no-width`. Add `-v` for per-stage debug logging.

### Tuning the bandwidth extension (avoiding "metallic")

Pure harmonic synthesis sounds metallic on harmonic-rich material (e.g. electric guitar) — see the
DSP/lit notes in the spike report. The BWE knobs (and a good starting recipe validated by ear on a
band-limited track) are:

- `--bwe-mix-db` (default −15) — overall HF lift level; **lower = subtler**.
- `--bwe-drive` (default 1.5) — harmonic drive; **lower = cleaner** (fewer high-order "buzzy" harmonics).
- `--bwe-tilt` (default −9) — HF decay dB/oct; **steeper (−12) = less top sizzle**.
- `--bwe-cap-db` (default 8) — per-octave safety cap; **lower reins in bright content**.
- `--bwe-noise` (default 0) — **stochastic "air" blend 0..1**; the anti-metallic control. Mixes in
  envelope-shaped noise (air on the notes, not constant hiss) to break the harmonic comb.

Recommended starting point for a metallic-prone, ~5 kHz-limited source:
```bash
--bwe-drive 1.0 --bwe-mix-db -20 --bwe-tilt -12 --bwe-cap-db 5 --bwe-noise 0.5
```

## The chain

```
de-hiss  →  bandwidth extension  →  match-EQ  →  width  →  LUFS normalize  →  true-peak limit
(log-MMSE)  (harmonic synthesis)   (LTAS ratio)  (M/S)     (BS.1770)          (oversampled)
```

Loudness + limiter are **last** (in that order): width changes level — turning mono into stereo
raises the BS.1770 reading ~3 dB — so we normalize the *final* signal and guarantee the true-peak
ceiling last. Every layer is faithful — it attenuates, shapes, or synthesizes from the existing
signal; nothing is hallucinated.

## What the verification shows (synthetic fixture)

`make-test` builds a bright modern reference and a degraded "legacy" copy (8 kHz rolloff, thin
bass, hiss, mono, quiet). Remastering the legacy copy:

- **LUFS**: −21.9 → **−14.0** (exact target); true-peak ceiling held at −1 dBTP.
- **HF energy (10 kHz–Nyquist)**: bandwidth extension adds **~+8.6 dB** (bake-off, BWE in isolation).
- **Tonal match**: the remastered LTAS tracks the modern reference across 200 Hz–10 kHz (see
  `out/plots/ltas.png`).
- **Mono-safe**: L+R sum deviates **0.00 dB** from the source mono.
- **Speed**: the **classical chain** (this POC — no learned BWE wired up) runs at **RTF ≈ 0.09**
  (a 9 s clip in ~0.8 s) on an M-series laptop. A learned BWE model (AERO/FlashSR) would add its
  own inference cost on top — that RTF is still unmeasured on Apple Silicon (see the spike report).

### Process-ahead feasibility

```
$ legacy-remaster sim --rtf 0.087 --headstart 5 --duration 240
  buffer at start : 57.47s     verdict: stable (buffer grows)     max streamable: unbounded (rtf < 1)
```

At the measured RTF, a 5 s head-start pre-buffers ~57 s of audio and the buffer only grows — i.e.
the streaming "Quick Remaster" UX is comfortably feasible (the report's core thesis).

## Bandwidth-extension bake-off

```bash
legacy-remaster bakeoff data/old.m4a --out out/bakeoff
```

The classical harmonic-synthesis baseline always runs. **AERO** and **FlashSR** are honest
scaffolds — they detect whether `torch` + weights are wired up (`AERO_WEIGHTS` / `FLASHSR_WEIGHTS`
env vars) and are *skipped with a message* if not, rather than faking a result. To enable them,
`pip install -e '.[ml]'` and implement the model call in `remaster/bakeoff.py` (see that file's
docstring + the spike report's references).

## Known limitations / open questions

- **Deep bass** (30–100 Hz) is only partially recovered — the ±9 dB match-EQ clamp can't rebuild
  what isn't there. A dedicated **virtual-bass / harmonic bass synthesis** layer is future work.
- **Spectral-kurtosis** is a *proxy*, not proof of an artifact. It rises through the chain mostly
  because **de-hiss removes stationary (low-kurtosis) hiss**, letting the signal's real transient
  structure re-emerge (measured on the fixture: de-hiss 9→31; the bright modern *reference* is ~57;
  the full remaster lands at ~26, below de-hiss-alone thanks to the H-3 match-EQ taper). BWE in
  isolation barely moves it. Trust the ear, and compare to a reference — not the dull input.
- **De-hiss without a noise segment** uses a blind percentile estimate, which is safe but can dull
  very sustained tones. Prefer `--noise-start/--noise-dur` on a quiet intro/outro.
- The classical BWE is a **baseline**, not the destination — the bake-off exists to quantify how
  much a learned model (AERO/FlashSR) improves on it.

## Layout

```
remaster/        package: audioio, dsp, dehiss, bwe_classical, match_eq, loudness, width,
                 verify, pipeline, synth, sim, bakeoff, cli
tests/           pytest suite (STFT round-trip, LUFS accuracy, peak ceiling, mono-sum,
                 de-hiss null test, BWE HF gain, process-ahead math, m4a decode)
data/            drop your own tracks here (git-ignored)
out/             generated audio + plots (git-ignored)
```

## License notes (project LD-9)

This is a clean-room reimplementation. **Matchering is GPL-3.0** (reference-only under LD-9) — the
match-EQ here reimplements the LTAS-ratio idea from scratch, no Matchering code. Any learned model
**weights** trained on MUSDB18-HQ are non-commercial (reference-only); the model *code* is typically
MIT/Apache. Verify both code and weights licenses before shipping anything derived from this.

## Dev

```bash
pip install -e '.[dev]'
ruff check .
pytest
```
