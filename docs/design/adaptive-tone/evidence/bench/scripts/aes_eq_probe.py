"""Audiobox Aesthetics EQ-sensitivity probe (feasibility study, read-only on the repo).

usage: python -I aes_eq_probe.py <checkpoint.pt> <out.json> <clip.wav:start_s> [...]

For each clip: a 30 s excerpt, rendered through simple RBJ-cookbook EQ variants, each variant
loudness-matched to the flat excerpt by BS.1770 integrated loudness (pyloudnorm). Every variant is
scored per 10 s window (the package's own window/hop), on the four axes. Controls: level-only
changes (no loudness match), excerpt-alignment shifts, and an exact repeat (run-to-run).
"""

import json
import sys
import time

import numpy as np
import pyloudnorm as pyln
import scipy.signal as ss
import soundfile as sf
import torch

from audiobox_aesthetics.infer import AesPredictor

AXES = ["PQ", "PC", "CE", "CU"]
EXCERPT_S = 30.0


def rbj(kind, f0, gain_db, fs, q=0.7071, slope=1.0):
    """RBJ Audio-EQ-Cookbook biquad (b, a)."""
    a_lin = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * f0 / fs
    cw, sw = np.cos(w0), np.sin(w0)
    if kind == "peak":
        alpha = sw / (2 * q)
        b = [1 + alpha * a_lin, -2 * cw, 1 - alpha * a_lin]
        a = [1 + alpha / a_lin, -2 * cw, 1 - alpha / a_lin]
    else:
        alpha = sw / 2 * np.sqrt((a_lin + 1 / a_lin) * (1 / slope - 1) + 2)
        sq = 2 * np.sqrt(a_lin) * alpha
        if kind == "low":
            b = [a_lin * ((a_lin + 1) - (a_lin - 1) * cw + sq),
                 2 * a_lin * ((a_lin - 1) - (a_lin + 1) * cw),
                 a_lin * ((a_lin + 1) - (a_lin - 1) * cw - sq)]
            a = [(a_lin + 1) + (a_lin - 1) * cw + sq,
                 -2 * ((a_lin - 1) + (a_lin + 1) * cw),
                 (a_lin + 1) + (a_lin - 1) * cw - sq]
        else:  # high shelf
            b = [a_lin * ((a_lin + 1) + (a_lin - 1) * cw + sq),
                 -2 * a_lin * ((a_lin - 1) + (a_lin + 1) * cw),
                 a_lin * ((a_lin + 1) + (a_lin - 1) * cw - sq)]
            a = [(a_lin + 1) - (a_lin - 1) * cw + sq,
                 2 * ((a_lin - 1) - (a_lin + 1) * cw),
                 (a_lin + 1) - (a_lin - 1) * cw - sq]
    b, a = np.array(b), np.array(a)
    return b / a[0], a / a[0]


# name -> list of (kind, f0, gain, q)
VARIANTS = {
    "flat": [],
    "bass+3 (LS150)": [("low", 150, 3, None)],
    "bass+6 (LS150)": [("low", 150, 6, None)],
    "bass-3 (LS150)": [("low", 150, -3, None)],
    "bass-6 (LS150)": [("low", 150, -6, None)],
    "treble+3 (HS6k)": [("high", 6000, 3, None)],
    "treble+6 (HS6k)": [("high", 6000, 6, None)],
    "treble-3 (HS6k)": [("high", 6000, -3, None)],
    "treble-6 (HS6k)": [("high", 6000, -6, None)],
    "tilt+3 (bright)": [("low", 1000, -3, None), ("high", 1000, 3, None)],
    "tilt-3 (dark)": [("low", 1000, 3, None), ("high", 1000, -3, None)],
    "harsh +9@3k": [("peak", 3000, 9, 1.4)],
    "mud +6@250": [("peak", 250, 6, 1.0)],
    "air+6 (HS10k)": [("high", 10000, 6, None)],
}


def apply_eq(x, fs, chain):
    y = x.copy()
    for kind, f0, g, q in chain:
        b, a = rbj(kind, f0, g, fs, q=q or 0.7071)
        y = ss.lfilter(b, a, y, axis=0)
    return y


def score_windows(pred, x, fs):
    """Scores per 10 s window: list of {axis: value}."""
    out = []
    win = int(10 * fs)
    for start in range(0, x.shape[0] - win + 1, win):
        seg = torch.from_numpy(np.ascontiguousarray(x[start:start + win].T)).float()
        row = pred.forward([{"path": seg, "sample_rate": fs}])[0]
        out.append({k: row[k] for k in AXES})
    return out


def mean_scores(rows):
    return {k: float(np.mean([r[k] for r in rows])) for k in AXES}


def main():
    ckpt, out_path = sys.argv[1], sys.argv[2]
    clips = [(a.rsplit(":", 1)[0], float(a.rsplit(":", 1)[1])) for a in sys.argv[3:]]
    device = torch.device("mps") if torch.backends.mps.is_available() else torch.device("cpu")
    result = {"device": str(device), "torch": torch.__version__, "clips": {}}

    t0 = time.perf_counter()
    pred = AesPredictor(checkpoint_pth=ckpt)  # picks MPS when available
    result["load_s"] = time.perf_counter() - t0

    for path, start in clips:
        x_all, fs = sf.read(path, dtype="float64", always_2d=True)
        n0, n = int(start * fs), int(EXCERPT_S * fs)
        x = x_all[n0:n0 + n]
        meter = pyln.Meter(fs)
        ref_lufs = meter.integrated_loudness(x)
        clip = {"fs": fs, "start_s": start, "ref_lufs": ref_lufs, "variants": {}, "controls": {}}

        for name, chain in VARIANTS.items():
            y = apply_eq(x, fs, chain)
            gain_db = ref_lufs - meter.integrated_loudness(y)
            y = y * 10 ** (gain_db / 20)
            t1 = time.perf_counter()
            rows = score_windows(pred, y, fs)
            dt = time.perf_counter() - t1
            clip["variants"][name] = {"match_gain_db": gain_db, "peak_dbfs": 20 * np.log10(np.max(np.abs(y))),
                                      "windows": rows, "mean": mean_scores(rows), "score_s": dt}

        # Controls: run-to-run (exact repeat), level-only changes, alignment shifts.
        clip["controls"]["repeat"] = mean_scores(score_windows(pred, x, fs))
        for g in (-6.0, -1.0, 1.0):
            clip["controls"][f"gain{g:+.0f}dB"] = mean_scores(score_windows(pred, x * 10 ** (g / 20), fs))
        for shift in (0.5, 1.0, 2.0):
            ns = int((start + shift) * fs)
            clip["controls"][f"shift+{shift}s"] = mean_scores(score_windows(pred, x_all[ns:ns + n], fs))
        result["clips"][path.rsplit("/", 1)[-1]] = clip
        print("done", path, flush=True)

    with open(out_path, "w") as f:
        json.dump(result, f, indent=1)


if __name__ == "__main__":
    main()
