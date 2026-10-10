"""
geq.py -- prototype of an accurate 31-band third-octave cascade graphic EQ (ACGE family).

Reference design family (cited in dsp-plan-check.md):
  * Valimaki & Liski, "Accurate Cascade Graphic Equalizer", IEEE SPL 24(2):176-180, 2017
    -- one 2nd-order bell per band; interaction matrix B sampled at the band centres AND the
       geometric midpoints; gains by least squares g = pinv(B) t; one refinement iteration
       (B rebuilt with the first-pass gains); prototype gain 17 dB for the first B.
  * Liski & Valimaki, "The Quest for the Best Graphic Equalizer", DAFx-17 -- third-octave extension.
  * Liski, Ramo & Valimaki, "Graphic EQ design with symmetric biquad filters", WASPAA 2019, and
    Ramo, Liski & Valimaki, "Third-octave and Bark GEQ design with symmetric band filters",
    Appl. Sci. 10(4):1222, 2020 -- band filters with a PRESCRIBED NYQUIST GAIN (Orfanidis 1997)
    so the top bands stay symmetric on a log axis instead of being cramped to 0 dB at fs/2.

Everything here is float64 numpy; the formulas are what the C++ port must reproduce.
"""
from __future__ import annotations

import numpy as np

NB = 31
# Exact base-10 third-octave centres (ISO 266 preferred numbers are rounded versions of these).
FC = 10.0 ** (1.3 + 0.1 * np.arange(NB))  # 19.95 Hz ... 19953 Hz
FC_NOMINAL = np.array([20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500,
                       630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000,
                       10000, 12500, 16000, 20000], dtype=float)
FMID = np.sqrt(FC[:-1] * FC[1:])  # 30 geometric midpoints
# The 61 design/evaluation points of the ACGE: centres interleaved with midpoints.
FPTS = np.empty(2 * NB - 1)
FPTS[0::2] = FC
FPTS[1::2] = FMID

SAMPLE_RATES = [44100.0, 48000.0, 88200.0, 96000.0, 176400.0, 192000.0]


# --------------------------------------------------------------------------------------------
# Band filters
# --------------------------------------------------------------------------------------------
def bell_bilinear(fc, gdb, fs, c):
    """Bilinear (RBJ-equivalent, symmetric boost/cut) bell; bandwidth B = c*w0 at the half-dB
    gain points (the ACGE convention). Nyquist gain is forced to 0 dB (the 'cramping')."""
    fc = np.atleast_1d(fc).astype(float)
    gdb = np.atleast_1d(gdb).astype(float) * np.ones_like(fc)
    w0 = 2 * np.pi * fc / fs
    Bw = np.minimum(c * w0, 0.98 * np.pi)
    G = 10.0 ** (gdb / 20.0)
    beta = np.tan(Bw / 2.0) / np.sqrt(G)
    cw = np.cos(w0)
    a0 = 1 + beta
    b = np.stack([(1 + G * beta) / a0, -2 * cw / a0, (1 - G * beta) / a0], axis=-1)
    a = np.stack([np.ones_like(a0), -2 * cw / a0, (1 - beta) / a0], axis=-1)
    return b, a


def bell_orfanidis(fc, gdb, fs, c):
    """Orfanidis (JAES 45(6), 1997) peaking EQ with PRESCRIBED NYQUIST GAIN: matches the analog
    prototype at DC (G0=1), at w0 (G), at the half-dB bandwidth Dw = c*w0 (GB = sqrt(G)) and at
    Nyquist (G1 = analog gain at pi). Formulas as in Orfanidis' peq.m. Symmetric: the cut is the
    exact inverse of the boost."""
    fc = np.atleast_1d(fc).astype(float)
    gdb = np.atleast_1d(gdb).astype(float) * np.ones_like(fc)
    b = np.zeros(fc.shape + (3,))
    a = np.zeros(fc.shape + (3,))
    b[..., 0] = 1.0
    a[..., 0] = 1.0
    nz = np.abs(gdb) > 1e-9
    if not np.any(nz):
        return b, a
    w0 = 2 * np.pi * fc[nz] / fs
    Dw = c * w0
    G0 = 1.0
    G = 10.0 ** (gdb[nz] / 20.0)
    GB = np.sqrt(G * G0)
    F = np.abs(G**2 - GB**2)
    G00 = np.abs(G**2 - G0**2)
    F00 = np.abs(GB**2 - G0**2)
    num = G0**2 * (w0**2 - np.pi**2) ** 2 + G**2 * F00 * np.pi**2 * Dw**2 / F
    den = (w0**2 - np.pi**2) ** 2 + F00 * np.pi**2 * Dw**2 / F
    G1 = np.sqrt(num / den)
    G01 = np.abs(G**2 - G0 * G1)
    G11 = np.abs(G**2 - G1**2)
    F01 = np.abs(GB**2 - G0 * G1)
    F11 = np.abs(GB**2 - G1**2)
    W2 = np.sqrt(G11 / G00) * np.tan(w0 / 2) ** 2
    DW = (1 + np.sqrt(F00 / F11) * W2) * np.tan(Dw / 2)
    C = F11 * DW**2 - 2 * W2 * (F01 - np.sqrt(F00 * F11))
    D = 2 * W2 * (G01 - np.sqrt(G00 * G11))
    A = np.sqrt((C + D) / F)
    Bc = np.sqrt((G**2 * C + GB**2 * D) / F)
    a0 = 1 + W2 + A
    b[nz, 0] = (G1 + G0 * W2 + Bc) / a0
    b[nz, 1] = -2 * (G1 - G0 * W2) / a0
    b[nz, 2] = (G1 - Bc + G0 * W2) / a0
    a[nz, 1] = -2 * (1 - W2) / a0
    a[nz, 2] = (1 + W2 - A) / a0
    return b, a


def highshelf_bilinear(fc, gdb, fs, S=1.0):
    """RBJ high shelf (for the 'band 31 as a shelf' variant), corner at fc."""
    A = 10 ** (gdb / 40.0)
    w0 = 2 * np.pi * fc / fs
    cw, sw = np.cos(w0), np.sin(w0)
    alpha = sw / 2 * np.sqrt((A + 1 / A) * (1 / S - 1) + 2)
    sa = 2 * np.sqrt(A) * alpha
    b0 = A * ((A + 1) + (A - 1) * cw + sa)
    b1 = -2 * A * ((A - 1) + (A + 1) * cw)
    b2 = A * ((A + 1) + (A - 1) * cw - sa)
    a0 = (A + 1) - (A - 1) * cw + sa
    a1 = 2 * ((A - 1) - (A + 1) * cw)
    a2 = (A + 1) - (A - 1) * cw - sa
    return np.array([b0, b1, b2]) / a0, np.array([1.0, a1 / a0, a2 / a0])


DESIGNS = {"bilinear": bell_bilinear, "orfanidis": bell_orfanidis}


def sos_db(b, a, f, fs):
    """dB magnitude of each section (rows of b, a) at frequencies f -> shape (nsec, nf)."""
    z1 = np.exp(-1j * 2 * np.pi * np.asarray(f) / fs)  # z^-1
    z2 = z1 * z1
    b = np.atleast_2d(b)
    a = np.atleast_2d(a)
    H = (b[:, 0:1] + b[:, 1:2] * z1 + b[:, 2:3] * z2) / (a[:, 0:1] + a[:, 1:2] * z1 + a[:, 2:3] * z2)
    return 20 * np.log10(np.abs(H))


# --------------------------------------------------------------------------------------------
# ACGE solve
# --------------------------------------------------------------------------------------------
def interleave_target(t31):
    t = np.empty(2 * NB - 1)
    t[0::2] = t31
    t[1::2] = 0.5 * (t31[:-1] + t31[1:])  # linear interpolation in dB on the log axis
    return t


def interaction_matrix(fs, c, design, gproto):
    """B[k, m] = dB response of band m (designed at gain gproto[m]) at point k, / gproto[m]."""
    gproto = np.broadcast_to(np.asarray(gproto, float), (NB,)).copy()
    small = np.abs(gproto) < 1e-3
    gproto[small] = 1e-3  # shape at vanishing gain (symmetric bells: the limit is well defined)
    b, a = DESIGNS[design](FC, gproto, fs, c)
    return (sos_db(b, a, FPTS, fs) / gproto[:, None]).T  # (61, 31)


_B0_CACHE: dict = {}


def acge_gains(t31, fs, c, design="orfanidis", gproto0=17.0, iters=1, weights=None):
    """Filter gains g (dB, NOT clamped to +-12) whose cascade best fits the 61-point target."""
    t = interleave_target(np.asarray(t31, float))
    key = (fs, c, design, gproto0)
    if key not in _B0_CACHE:
        _B0_CACHE[key] = interaction_matrix(fs, c, design, gproto0)
    B = _B0_CACHE[key]
    W = np.ones(2 * NB - 1) if weights is None else weights
    g = np.linalg.lstsq(B * W[:, None], t * W, rcond=None)[0]
    for _ in range(iters):
        B = interaction_matrix(fs, c, design, g)
        g = np.linalg.lstsq(B * W[:, None], t * W, rcond=None)[0]
    return g


def cascade(g, fs, c, design="orfanidis"):
    return DESIGNS[design](FC, g, fs, c)


def response_db(g, f, fs, c, design="orfanidis"):
    b, a = cascade(g, fs, c, design)
    return sos_db(b, a, f, fs).sum(axis=0)


# --------------------------------------------------------------------------------------------
# Metrics
# --------------------------------------------------------------------------------------------
DENSE_AUDIBLE = np.geomspace(FC[0], FC[-1], 4000)  # 20 Hz .. 20 kHz, ~1/400 oct


def target_interp(t31, f):
    """Log-linear interpolation of the 31 targets (what 'the line between the points' means)."""
    return np.interp(np.log10(f), np.log10(FC), t31)


def metrics(t31, g, fs, c, design="orfanidis"):
    t31 = np.asarray(t31, float)
    centre = response_db(g, FC, fs, c, design)
    pts = response_db(g, FPTS, fs, c, design)
    dense = response_db(g, DENSE_AUDIBLE, fs, c, design)
    return {
        "centre": float(np.max(np.abs(centre - t31))),
        "pts61": float(np.max(np.abs(pts - interleave_target(t31)))),
        "dense": float(np.max(np.abs(dense - target_interp(t31, DENSE_AUDIBLE)))),
        "gmax": float(np.max(np.abs(g))),
    }


# --------------------------------------------------------------------------------------------
# Headroom + predicted loudness
# --------------------------------------------------------------------------------------------
def peak_db(g, fs, c, design="orfanidis", npts=512, fmin=10.0):
    f = np.geomspace(fmin, 0.5 * fs * 0.999, npts)
    r = response_db(g, f, fs, c, design)
    return float(r.max()), float(f[np.argmax(r)])


def kweight_db(f):
    """BS.1770 K-weighting magnitude (stage 1 shelf + stage 2 RLB HPF), 48 kHz coefficients."""
    fs = 48000.0
    b1 = np.array([1.53512485958697, -2.69169618940638, 1.19839281085285])
    a1 = np.array([1.0, -1.69065929318241, 0.73248077421585])
    b2 = np.array([1.0, -2.0, 1.0])
    a2 = np.array([1.0, -1.99004745483398, 0.99007225036621])
    return sos_db(np.vstack([b1, b2]), np.vstack([a1, a2]), f, fs).sum(axis=0)


_LGRID = np.geomspace(20.0, 20000.0, 2000)
_KW = 10 ** (kweight_db(_LGRID) / 10)


def predicted_loudness_change_db(net_db_on_lgrid, slope_db_per_oct=-3.0):
    """K-weighted energy change of a long-term spectrum with the given slope (pink = -3 dB/oct).
    On a log-spaced grid, a -3 dB/oct PSD has equal energy per grid step."""
    w = _KW * 10 ** ((slope_db_per_oct + 3.0) * np.log2(_LGRID / 1000.0) / 10)
    return float(10 * np.log10(np.sum(w * 10 ** (net_db_on_lgrid / 10)) / np.sum(w)))


# --------------------------------------------------------------------------------------------
# Tone macros (decision 24)
# --------------------------------------------------------------------------------------------
TONE_NAMES = ["Bass", "Body", "Mids", "Presence", "Air"]
TONE_EDGES = np.array([150.0, 500.0, 2000.0, 6000.0])


def smoothstep_rc(u, width_oct):
    """Raised-cosine step 0 -> 1 over [-W/2, +W/2] octaves (C1-continuous)."""
    x = np.clip(u / width_oct, -0.5, 0.5)
    return 0.5 * (1 + np.sin(np.pi * x))


def tone_weights(f, width_oct=1.0):
    """W[k](f): partition of unity over log2 f. w_k = S(x - e_{k-1}) - S(x - e_k)."""
    x = np.log2(np.asarray(f, float))
    S = [smoothstep_rc(x - np.log2(e), width_oct) for e in TONE_EDGES]  # 4 steps
    w = [1 - S[0], S[0] - S[1], S[1] - S[2], S[2] - S[3], S[3]]
    return np.vstack(w)  # (5, nf)


def apply_tone(base31, tone5, width_oct=1.0):
    W = tone_weights(FC, width_oct)  # (5, 31)
    return np.clip(np.asarray(base31) + np.asarray(tone5) @ W, -12, 12)


# --------------------------------------------------------------------------------------------
# The app's presets (EQPreset.swift formulas, evaluated at the nominal ISO centres)
# --------------------------------------------------------------------------------------------
def _presence(f):
    if 1000 <= f <= 4000:
        return 8 * np.sin((np.log10(f) - 3) / (np.log10(4000) - 3) * np.pi)
    if 4000 < f <= 8000:
        return 4 * np.sin((np.log10(8000) - np.log10(f)) / (np.log10(8000) - np.log10(4000)) * np.pi / 2)
    return 0.0


def _clarity(f):
    if 1000 <= f <= 8000:
        return 6 * np.sin((np.log10(f) - 3) / (np.log10(8000) - 3) * np.pi / 2)
    if 8000 < f <= 16000:
        return 4 * np.sin((np.log10(16000) - np.log10(f)) / (np.log10(16000) - np.log10(8000)) * np.pi / 2)
    return 0.0


def _warm(f):
    if 20 <= f <= 500:
        return 12 * (1 - np.exp(-np.log10(f) / 1.5))
    if 500 < f <= 2000:
        return 8 * np.exp(-(f - 500) / 1500)
    return 0.0


def _loudness(f):
    bass = 4 * np.cos((np.log10(f) - np.log10(20)) / (np.log10(500) - np.log10(20)) * np.pi / 2) if f <= 500 else 0.0
    if f >= 3150:
        n = min(1.0, (np.log10(f) - np.log10(3150)) / (np.log10(12500) - np.log10(3150)))
        treble = 3 * np.sin(n * np.pi / 2)
    else:
        treble = 0.0
    return bass + treble


def _vocal(f):
    if 500 <= f <= 3150:
        return 6 * np.sin((np.log10(f) - np.log10(500)) / (np.log10(3150) - np.log10(500)) * np.pi / 2)
    if 3150 < f <= 8000:
        return 6 * np.sin((np.log10(8000) - np.log10(f)) / (np.log10(8000) - np.log10(3150)) * np.pi / 2)
    return 0.0


def _studio(f):
    if f <= 8000:
        return 0.0
    n = min(1.0, (np.log10(f) - np.log10(8000)) / (np.log10(16000) - np.log10(8000)))
    return 2 * np.sin(n * np.pi / 2)


PRESETS = {
    name: np.array([fn(f) for f in FC_NOMINAL], dtype=np.float32).astype(float)
    for name, fn in [("Presence", _presence), ("Clarity", _clarity), ("Warm", _warm),
                     ("Loudness", _loudness), ("Vocal", _vocal), ("Studio", _studio)]
}


def test_curves():
    cur = {f"preset:{k}": v for k, v in PRESETS.items()}
    for idx in [0, 8, 17, 26, 29, 30]:
        t = np.zeros(NB)
        t[idx] = 12
        cur[f"single+12@{FC_NOMINAL[idx]:g}Hz"] = t
    t = np.zeros(NB)
    t[17] = -12
    cur["single-12@1000Hz"] = t
    cur["alternating+-12"] = np.where(np.arange(NB) % 2 == 0, 12.0, -12.0)
    cur["alternating-+12"] = -cur["alternating+-12"]
    cur["pairs ++--"] = np.where((np.arange(NB) // 2) % 2 == 0, 12.0, -12.0)
    cur["all+12"] = np.full(NB, 12.0)
    cur["broadband+3"] = np.full(NB, 3.0)
    cur["tone B+6 Bo-3 M0 P+4 A+6"] = apply_tone(np.zeros(NB), [6, -3, 0, 4, 6])
    cur["tone all+12"] = apply_tone(np.zeros(NB), [12, 12, 12, 12, 12])
    cur["tone B+12 Bo-12 M+12 P-12 A+12"] = apply_tone(np.zeros(NB), [12, -12, 12, -12, 12])
    cur["Warm + tone Air+6"] = apply_tone(PRESETS["Warm"], [0, 0, 0, 0, 6])
    return cur
