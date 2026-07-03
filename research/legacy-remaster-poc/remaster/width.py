"""Stereo width — mono->pseudo-stereo and stereo widening, mono-compatible by design.

Both paths leave the Mid (L+R) untouched and only synthesize/scale the Side, so the
mono sum is preserved (the spike report's hard requirement: L+R within +/-1 dB of source).
"""
from __future__ import annotations

import numpy as np
from scipy.signal import lfilter

from .audioio import is_stereo, to_mono


def _schroeder_allpass(x: np.ndarray, delay: int, g: float) -> np.ndarray:
    """Single Schroeder all-pass: flat magnitude, scrambled phase -> decorrelation."""
    b = np.zeros(delay + 1)
    a = np.zeros(delay + 1)
    b[0], b[delay] = -g, 1.0
    a[0], a[delay] = 1.0, -g
    return lfilter(b, a, x)


def decorrelate(x: np.ndarray, sr: int) -> np.ndarray:
    """Chain of all-pass sections -> a decorrelated copy with the same magnitude spectrum."""
    delays_ms = [4.77, 7.13, 11.7, 19.3]  # mutually-prime-ish, classic reverb-diffusion values
    gains = [0.7, 0.65, 0.6, 0.55]
    y = x.copy()
    for d_ms, g in zip(delays_ms, gains, strict=True):
        y = _schroeder_allpass(y, max(1, int(d_ms * 1e-3 * sr)), g)
    return y


def mono_to_pseudo_stereo(x_mono: np.ndarray, sr: int, width: float = 0.4) -> np.ndarray:
    """mono (n,) -> (n, 2). Side = width * decorrelated(mono); mono sum = 2*mid exactly."""
    side = decorrelate(x_mono, sr)
    # normalize side energy to the mono so `width` is meaningful
    side *= (np.std(x_mono) + 1e-12) / (np.std(side) + 1e-12)
    L = x_mono + width * side
    R = x_mono - width * side
    return np.stack([L, R], axis=-1)


def widen_stereo(x_stereo: np.ndarray, amount: float = 0.3) -> np.ndarray:
    """Increase Side level by `amount`. Mid (mono sum) unchanged."""
    L, R = x_stereo[:, 0], x_stereo[:, 1]
    M, S = 0.5 * (L + R), 0.5 * (L - R)
    S *= (1.0 + amount)
    return np.stack([M + S, M - S], axis=-1)


def widen(x: np.ndarray, sr: int, width: float = 0.4) -> np.ndarray:
    """Dispatch: mono -> pseudo-stereo, stereo -> widen."""
    if is_stereo(x):
        return widen_stereo(x, amount=width)
    mono = to_mono(x)
    return mono_to_pseudo_stereo(mono, sr, width=width)


def mono_sum_deviation_db(x_stereo: np.ndarray, x_ref_mono: np.ndarray) -> float:
    """RMS-dB deviation of the (L+R) mono sum from a reference mono signal.
    The widening should keep this near 0 dB (mono compatibility)."""
    s = x_stereo[:, 0] + x_stereo[:, 1]
    ref = 2.0 * x_ref_mono[: len(s)]
    rs = np.sqrt(np.mean(s[: len(ref)] ** 2)) + 1e-20
    rr = np.sqrt(np.mean(ref ** 2)) + 1e-20
    return 20.0 * np.log10(rs / rr)
