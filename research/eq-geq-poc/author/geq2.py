"""geq2.py -- v2 prototype helpers (builds on ../geq.py; the band filter, solve and Tone are unchanged).
Adds: per-pass error tracking, the Rämö-style command set, finished-coefficient (k, m1) SVF responses,
and the BS.1770 block tools used by the loudness-neutral predictor."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import numpy as np
from geq import (NB, FC, FC_NOMINAL, FPTS, SAMPLE_RATES, DESIGNS, PRESETS, interleave_target,
                 interaction_matrix, sos_db, response_db, cascade, tone_weights, apply_tone, bell_bilinear)

C = 0.40                                   # bandwidth factor (B = 0.40 w0 at the half-dB points)
W61 = np.ones(2 * NB - 1); W61[1::2] = 0.5  # WLS weights: centres 1, midpoints 0.5
GPROTO = 17.0
GUARD_DB = 1e-3                            # |g| below this uses a +-1e-3 dB prototype (no 0/0)


def solve_passes(t31, fs, passes=8):
    """Return the list of gain vectors after 0..passes refinement passes (index 0 = first solve)."""
    t = interleave_target(np.asarray(t31, float))
    B = interaction_matrix(fs, C, "bilinear", GPROTO)
    out = []
    g = np.linalg.lstsq(B * W61[:, None], t * W61, rcond=None)[0]; out.append(g)
    for _ in range(passes):
        gp = np.where(np.abs(g) < GUARD_DB, np.where(g >= 0, GUARD_DB, -GUARD_DB), g)
        B = interaction_matrix(fs, C, "bilinear", gp)
        g = np.linalg.lstsq(B * W61[:, None], t * W61, rcond=None)[0]; out.append(g)
    return out


def design(t31, fs, passes=3):
    return solve_passes(t31, fs, passes)[-1]


def centre_err(t31, g, fs):
    return float(np.max(np.abs(response_db(g, FC, fs, C, "bilinear") - t31)))


# ---------------- command sets ----------------
def ramo_set(rng, n_binary=500, n_int=500):
    """Rämö et al. 2020 protocol: half 'extreme' {-12, 0, +12}, half random integers in [-12, 12]."""
    b = rng.choice([-12.0, 0.0, 12.0], size=(n_binary, NB))
    i = rng.integers(-12, 13, size=(n_int, NB)).astype(float)
    return list(b) + list(i)


def hard_set():
    s = {}
    alt = np.where(np.arange(NB) % 2 == 0, 12.0, -12.0)
    s["alternating"] = alt; s["alternating-neg"] = -alt
    for ph in range(3):
        t = np.full(NB, 12.0); t[np.arange(NB) % 3 == ph] = -12.0
        s[f"every-third-down/{ph}"] = t; s[f"every-third-up/{ph}"] = -t
    for k in [5, 10, 15, 20, 25, 28, 29, 30]:
        t = np.full(NB, -12.0); t[k:] = 12.0
        s[f"cliff@{k}"] = t; s[f"cliff@{k}-neg"] = -t
    for k in [0, 1, 29, 30]:
        t = np.zeros(NB); t[k] = 12.0; s[f"single+12@{k}"] = t
    t = np.zeros(NB); t[29] = -12; t[30] = 12; s["edge -12/+12 (16k/20k)"] = t
    s["all+12"] = np.full(NB, 12.0); s["all-12"] = np.full(NB, -12.0)
    bdir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../review/breaker/")
    for f in ["worst_cmd_long.npy", "worst_cmd_44100.npy", "worst_cmd_48000.npy", "worst_cmd_192000.npy"]:
        p = bdir + f
        if os.path.exists(p): s["breaker " + f[:-4]] = np.load(p).astype(float)
    return s


def smooth_set(rng, n=200):
    out = []
    xs = np.log2(FC)
    for _ in range(n):
        knots = np.sort(rng.uniform(xs[0], xs[-1], 6)); vals = rng.uniform(-12, 12, 6)
        out.append(np.clip(np.interp(xs, knots, vals), -12, 12))
    return out


def tone_set(rng, n=100):
    return [apply_tone(np.zeros(NB), rng.uniform(-12, 12, 5)) for _ in range(n)]


# ---------------- finished SVF coefficients ----------------
def k0_of(fs):
    w0 = 2 * np.pi * FC / fs
    return 2 * np.tan(C * w0 / 2) / np.sin(w0), np.tan(w0 / 2)


def km_of(g, fs):
    """Finished per-band SVF bell coefficients (k, m1) for filter gains g (dB)."""
    k0, _ = k0_of(fs)
    A = 10 ** (np.asarray(g) / 40)
    k = k0 / A
    return k, k * (A * A - 1)


def svf_cascade_cplx(k, m1, fs, f):
    """H(f) of the SVF cascade with per-band (k, m1); g = tan(w0/2) fixed per band."""
    _, gt = k0_of(fs)
    z1 = np.exp(-1j * 2 * np.pi * np.asarray(f) / fs)
    H = np.ones(len(f), complex)
    for m in range(NB):
        s = (1 - z1) / (1 + z1) / gt[m]
        H *= 1 + m1[m] * s / (s * s + k[m] * s + 1)
    return H


def svf_cascade_db(k, m1, fs, f):
    return 20 * np.log10(np.abs(svf_cascade_cplx(k, m1, fs, f)))
