"""Compare an original vs its remaster and quantify what changed — so the difference can be
analyzed offline (spectra, the added/removed residual, per-octave deltas, brightness/noisiness)
without listening. This is the tool for diagnosing artifacts like "metallic" or "crispy" HF.
"""
from __future__ import annotations

import logging
import os

import numpy as np

from . import dsp, verify
from .audioio import rms_db, to_mono

log = logging.getLogger(__name__)

# centers of the standard octave bands
_OCT_CENTERS = [31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]


def _level_match(orig_mono: np.ndarray, rem_mono: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Trim to common length and scale `rem` to the same RMS as `orig`, so the comparison is
    about *content/tone*, not the loudness change the remaster applied."""
    n = min(len(orig_mono), len(rem_mono))
    o, r = orig_mono[:n], rem_mono[:n]
    g = (np.sqrt(np.mean(o ** 2)) + 1e-20) / (np.sqrt(np.mean(r ** 2)) + 1e-20)
    return o, r * g


def octave_table(
    orig_mono: np.ndarray, rem_mono: np.ndarray, sr: int
) -> list[tuple[float, float, float, float]]:
    """Per-octave energy (dB) for orig and remaster + delta. Returns (fc, orig_db, rem_db, delta)."""
    fo, po = dsp.ltas(orig_mono, sr)
    _, pr = dsp.ltas(rem_mono, sr)
    rows = []
    for fc in _OCT_CENTERS:
        lo, hi = fc / np.sqrt(2), fc * np.sqrt(2)
        m = (fo >= lo) & (fo < hi)
        if not m.any():
            continue
        eo = 10 * np.log10(po[m].sum() + 1e-20)
        er = 10 * np.log10(pr[m].sum() + 1e-20)
        rows.append((fc, eo, er, er - eo))
    return rows


def spectral_centroid_hz(x: np.ndarray, sr: int, n_fft: int = 2048) -> float:
    """Energy-weighted mean frequency — a "brightness" proxy."""
    mag = np.abs(dsp.stft(to_mono(x), n_fft, n_fft // 4)).mean(axis=0)
    f = dsp.rfftfreqs(n_fft, sr)
    return float((f * mag).sum() / (mag.sum() + 1e-20))


def hf_flatness(x: np.ndarray, sr: int, fmin: float = 8000.0, n_fft: int = 2048) -> float:
    """Spectral flatness above `fmin` (geometric/arithmetic mean of power). ~1.0 = noise-like
    (flat → "hiss/crispy"); ~0 = tonal. High flatness in synthesized HF flags hiss-like content."""
    X = np.abs(dsp.stft(to_mono(x), n_fft, n_fft // 4))
    f = dsp.rfftfreqs(n_fft, sr)
    p = (X[:, f >= fmin] ** 2).mean(axis=0) + 1e-20
    return float(np.exp(np.mean(np.log(p))) / np.mean(p))


def compare(orig: np.ndarray, rem: np.ndarray, sr: int, out_dir: str) -> dict:
    """Write comparison plots to out_dir and return a metrics dict."""
    os.makedirs(out_dir, exist_ok=True)
    o_full, r_full = to_mono(orig), to_mono(rem)
    o, r = _level_match(o_full, r_full)
    residual = r - o  # the level-matched signal that was added/removed

    verify.plot_ltas(
        {"original": o, "remastered": r, "added/removed (residual)": residual},
        sr, os.path.join(out_dir, "compare_ltas.png"), "LTAS: original vs remastered vs residual",
    )
    verify.plot_spectrogram(o, sr, os.path.join(out_dir, "spec_original.png"), "Original")
    verify.plot_spectrogram(r, sr, os.path.join(out_dir, "spec_remastered.png"), "Remastered")
    verify.plot_spectrogram(
        residual, sr, os.path.join(out_dir, "spec_residual.png"), "Residual (what changed)"
    )

    rows = octave_table(o, r, sr)
    return {
        "residual_level_db": rms_db(residual) - rms_db(o),     # how loud the change is vs the program
        "centroid_orig_hz": spectral_centroid_hz(o, sr),
        "centroid_rem_hz": spectral_centroid_hz(r, sr),
        "hf_flatness_orig": hf_flatness(o, sr),
        "hf_flatness_rem": hf_flatness(r, sr),
        "hf_flatness_residual": hf_flatness(residual, sr),
        "octave_table": rows,
    }


def format_report(metrics: dict) -> str:
    m = metrics
    co, cr = m["centroid_orig_hz"], m["centroid_rem_hz"]
    fo, fr, fres = m["hf_flatness_orig"], m["hf_flatness_rem"], m["hf_flatness_residual"]
    lines = [
        "  -- original vs remastered ------------------------",
        f"    residual level  {m['residual_level_db']:+.1f} dB vs program (size of the change)",
        f"    brightness      {co:.0f} -> {cr:.0f} Hz (spectral centroid)",
        f"    HF flatness>8k  {fo:.3f} -> {fr:.3f}  (residual {fres:.3f}; ~1=noise/hiss, ~0=tonal)",
        "",
        f"    {'band':>8} {'orig dB':>9} {'rem dB':>9} {'delta':>8}",
    ]
    for fc, eo, er, d in m["octave_table"]:
        flag = "  <-- big HF lift" if (fc >= 8000 and d >= 6) else ""
        lines.append(f"    {fc:>8.0f} {eo:>9.1f} {er:>9.1f} {d:>+8.1f}{flag}")
    lines.append("  --------------------------------------------------")
    return "\n".join(lines)
