"""Extension of the probe: does Production Quality have an optimum, or does it keep rising?

Sweeps a 6 kHz high shelf, a 150 Hz low shelf and a 3 kHz peak from -12 to +12 dB (loudness-matched),
on the same excerpts. usage: python -I aes_eq_sweep.py <checkpoint.pt> <clip.wav:start_s> [...]
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # our own scripts dir only

import numpy as np  # noqa: E402
import pyloudnorm as pyln  # noqa: E402
import soundfile as sf  # noqa: E402

import aes_eq_probe as probe  # noqa: E402
from audiobox_aesthetics.infer import AesPredictor  # noqa: E402

GAINS = [-12, -9, -6, -3, 0, 3, 6, 9, 12]
FAMILIES = {"HS6k": ("high", 6000, None), "LS150": ("low", 150, None), "PK3k Q1.4": ("peak", 3000, 1.4)}


def main():
    pred = AesPredictor(checkpoint_pth=sys.argv[1])
    for arg in sys.argv[2:]:
        path, start = arg.rsplit(":", 1)
        x_all, fs = sf.read(path, dtype="float64", always_2d=True)
        x = x_all[int(float(start) * fs): int((float(start) + 30) * fs)]
        meter = pyln.Meter(fs)
        ref = meter.integrated_loudness(x)
        print(f"\n{os.path.basename(path)}  (PQ / CE by gain {GAINS})")
        for fam, (kind, f0, q) in FAMILIES.items():
            pq, ce = [], []
            for g in GAINS:
                y = probe.apply_eq(x, fs, [(kind, f0, g, q)] if g else [])
                y = y * 10 ** ((ref - meter.integrated_loudness(y)) / 20)
                m = probe.mean_scores(probe.score_windows(pred, y, fs))
                pq.append(m["PQ"])
                ce.append(m["CE"])
            best = GAINS[int(np.argmax(pq))]
            print(f"  {fam:10s} PQ " + " ".join(f"{v:5.2f}" for v in pq) + f"   argmax PQ at {best:+d} dB")
            print(f"  {'':10s} CE " + " ".join(f"{v:5.2f}" for v in ce))


if __name__ == "__main__":
    main()
