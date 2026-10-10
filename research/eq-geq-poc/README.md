# EQ — 31-band graphic EQ reference prototype (Sprint EQ)

This is the Python reference for the engine in
[docs/design/eq-lens/plan/engine-plan.md](../../docs/design/eq-lens/plan/engine-plan.md):

- one bilinear bell per band at a bandwidth of 0.40·fc;
- a weighted least-squares interaction solve with 5 refinement passes;
- finished-(k, m1) state-variable-filter coefficient smoothing;
- a gated 1/24-octave BS.1770 loudness predictor.

**EQ1a ports this design to C++. The prototype is the oracle the C++ gate tests are checked against.**

- `author/`: the plan author's v2 scripts (`geq.py` and `geq2.py` are the design; the rest are
  measurements) and their `results/`.
  - `run_all.sh` also compiles three C++ benchmarks (`cpp/`). Those stayed in the session scratchpad and
    are NOT in the repo: the strict pre-commit hook lints every C++ file as production code, and their
    results are recorded in `results/`.
  - `loudness_v2.py` reads the 7 tracks under `research/` via an absolute path.
- `fixtures/`: the breaker's adversarial command curves (`.npy`, 31 dB values per row). The C++ gates pin
  them:
  - `v3_worst_tau40.npy`, `v3_worst_tau10.npy` → `EQ_Transitions_Adversarial`;
  - `worst_cmd_*.npy` → the accuracy gates;
  - `worst_pair.npy` and `pairs.txt` → the original M1 pair.

Reviews and their scripts' findings: [docs/design/eq-lens/evidence/](../../docs/design/eq-lens/evidence/).
