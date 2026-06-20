# Bandwidth-extension bake-off — wiring up learned models

The bake-off (`remaster/bakeoff.py`) compares bandwidth-extension methods on the same input by
HF-energy gain, musical-noise (spectral kurtosis), and RTF. The **classical** harmonic-synthesis
baseline always runs. The learned runners (**AERO**, **FlashSR**) are honest scaffolds: until you
wire them up they report unavailable and are skipped — they never fake a result.

## How a runner is detected

Each learned runner subclasses `_TorchWeightsRunner` and is `available()` only when both hold:
1. `torch` imports (`pip install -e '.[ml]'`), and
2. its weights env var points at an existing file (`AERO_WEIGHTS`, `FLASHSR_WEIGHTS`).

When available, the bake-off calls `runner.run(x, sr) -> np.ndarray`.

## The `run()` contract

```
run(x: np.ndarray, sr: int) -> np.ndarray
```
- `x` is float64, shape `(n,)` mono or `(n, ch)`. `sr` is the working rate (44100 here).
- Return the **bandwidth-extended** signal, **same shape and sample rate** as the input
  (resample internally if the model runs at another rate, e.g. 48 kHz, and convert back).
- Must not mutate `x`.

## Wiring AERO (Mandel, Tal, Adi — ICASSP 2023, arXiv:2211.12232)

1. `pip install -e '.[ml]'`
2. Clone the model + get weights: <https://github.com/slp-rl/aero> (check the repo for the
   checkpoint + its license — weights trained on MUSDB18-HQ carry non-commercial terms; see
   the LD-9 note in the project root README — reference-only for now).
3. Set `export AERO_WEIGHTS=/path/to/aero.ckpt`.
4. Implement `AeroRunner.run()` in `remaster/bakeoff.py`: load the net once (cache on the
   instance), run inference (handle the model's native rate via `audioio.resample`), return
   the result at `sr`.

## Wiring FlashSR (Im & Nam — ICASSP 2025, arXiv:2501.10807)

Same steps with `FLASHSR_WEIGHTS` and the FlashSR repo. FlashSR is one-step distilled diffusion
(~22x faster than multi-step SR), the leading "AI-era" candidate to fit the streaming budget.

## Caveats

- **Faithful vs generative:** these models are generative — they can synthesize plausible HF that
  was never in the take. Judge on familiar material; expose a dry/wet "authenticity" control.
- **RTF:** measure `runner.run` time on the actual target Mac (Core ML / MPS / MLX) — published
  RTFs are NVIDIA/CPU. The bake-off already reports per-runner RTF; that is the number that matters.
- **Licensing:** model code is usually MIT/Apache, but weights ≠ code. Verify both before shipping.
