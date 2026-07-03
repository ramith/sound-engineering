"""Match-EQ: shape the target's long-term spectral balance toward a reference.

This is a clean-room reimplementation of the *idea* behind reference matching
(LTAS ratio -> smoothed corrective EQ). It does NOT use Matchering's code, which is
GPL-3.0 and therefore reference-only under the project's LD-9 license policy.

Shape-only: the corrective curve is pivoted to zero mean in the 200 Hz-2 kHz midband,
so this layer changes *tone* but not *loudness* (the LUFS stage owns level). Applied
zero-phase in the STFT domain for the POC; production would realize it as a cascade of
minimum-phase biquads to avoid pre-ringing (see spike report §5).
"""
from __future__ import annotations

import numpy as np

from . import dsp
from .audioio import as_2d, to_mono


def _hf_taper(freqs: np.ndarray, rolloff_hz: float | None) -> np.ndarray:
    """Raised-cosine taper: 1 below `rolloff_hz`, 0 by one octave above. None -> all ones.

    Above the rolloff the legacy signal is just the de-hiss residual (and synthesized BWE
    content); applying the match-EQ boost there would amplify that residual floor (the
    musical-noise driver, review H-3). So the corrective curve is faded out there and BWE
    owns the high end."""
    taper = np.ones_like(freqs)
    if rolloff_hz is None:
        return taper
    hi = rolloff_hz * 2.0
    band = (freqs > rolloff_hz) & (freqs < hi)
    taper[band] = 0.5 * (1.0 + np.cos(np.pi * np.log2(freqs[band] / rolloff_hz)))
    taper[freqs >= hi] = 0.0
    return taper


def corrective_curve(
    target: np.ndarray,
    reference: np.ndarray,
    sr: int,
    n_fft: int = 4096,
    smooth_frac: float = 1.0 / 3.0,
    max_boost_db: float = 9.0,
    max_cut_db: float = 9.0,
    rolloff_hz: float | None = None,
) -> tuple[np.ndarray, np.ndarray]:
    """Return (freqs, gain_db) — the smoothed, clamped, level-pivoted, HF-tapered match curve.

    Both signals reduced to mono for the curve (tone is a broadband property).
    """
    hop = n_fft // 4
    f, pt = dsp.ltas(to_mono(target), sr, n_fft, hop)
    _, pr = dsp.ltas(to_mono(reference), sr, n_fft, hop)
    pt_s = dsp.smooth_log(f, pt, smooth_frac)
    pr_s = dsp.smooth_log(f, pr, smooth_frac)
    gain_db = 10.0 * np.log10((pr_s + 1e-20) / (pt_s + 1e-20))  # power ratio -> dB
    # pivot to zero mean in the midband => shape-only, no net level change
    mid = (f >= 200) & (f <= 2000)
    if mid.any():
        gain_db = gain_db - np.median(gain_db[mid])
    gain_db = np.clip(gain_db, -max_cut_db, max_boost_db)
    gain_db = gain_db * _hf_taper(f, rolloff_hz)  # don't EQ the HF residual; BWE owns it
    return f, gain_db


def apply_curve(x: np.ndarray, sr: int, gain_db: np.ndarray, n_fft: int = 4096) -> np.ndarray:
    """Apply a per-bin gain curve (defined on the n_fft rfft grid) zero-phase via STFT."""
    gain = 10 ** (gain_db / 20)
    x2 = as_2d(x)
    hop = n_fft // 4
    out = np.empty_like(x2)
    for c in range(x2.shape[1]):
        X = dsp.stft(x2[:, c], n_fft, hop)
        out[:, c] = dsp.istft(X * gain[None, :], n_fft, hop, length=x2.shape[0])
    return out[:, 0] if x.ndim == 1 else out


def match_eq(
    target: np.ndarray,
    reference: np.ndarray,
    sr: int,
    n_fft: int = 4096,
    smooth_frac: float = 1.0 / 3.0,
    max_boost_db: float = 9.0,
    max_cut_db: float = 9.0,
    rolloff_hz: float | None = None,
) -> tuple[np.ndarray, tuple[np.ndarray, np.ndarray]]:
    """Match target's tonal balance to reference. Returns (eq'd_signal, (freqs, gain_db)).

    Pass `rolloff_hz` (e.g. the BWE-detected rolloff) to fade the correction out above it."""
    f, gain_db = corrective_curve(
        target, reference, sr, n_fft, smooth_frac, max_boost_db, max_cut_db, rolloff_hz
    )
    y = apply_curve(target, sr, gain_db, n_fft)
    return y, (f, gain_db)
