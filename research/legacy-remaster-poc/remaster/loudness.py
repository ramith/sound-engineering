"""Loudness: ITU-R BS.1770 integrated-loudness normalization + a true-peak limiter.

- LUFS normalization is a single static gain (transparent; the project's LD-17 stance
  is no program DRC by default).
- The limiter is an oversampled, look-ahead brickwall (offline -> look-ahead is free)
  that catches inter-sample (true) peaks, ceiling defaults to -1 dBTP.
"""
from __future__ import annotations

import numpy as np
import pyloudnorm as pyln
from scipy.ndimage import maximum_filter1d
from scipy.signal import resample_poly

from .audioio import as_2d


def integrated_lufs(x: np.ndarray, sr: int) -> float:
    meter = pyln.Meter(sr)
    data = x if x.ndim == 1 else as_2d(x)
    return float(meter.integrated_loudness(data))


def normalize_lufs(x: np.ndarray, sr: int, target_lufs: float = -14.0) -> tuple[np.ndarray, float, float]:
    """Static-gain normalize to target LUFS. Returns (y, measured_lufs, gain_db)."""
    measured = integrated_lufs(x, sr)
    if not np.isfinite(measured):
        return x, measured, 0.0
    gain_db = target_lufs - measured
    return x * (10 ** (gain_db / 20)), measured, gain_db


def true_peak_limit(
    x: np.ndarray,
    sr: int,
    ceiling_db: float = -1.0,
    oversample: int = 4,
    lookahead_ms: float = 1.5,
    release_ms: float = 50.0,
) -> tuple[np.ndarray, float]:
    """Oversampled look-ahead true-peak limiter. Returns (y, estimated_input_true_peak_dBTP).

    Correctness of the inter-sample-peak (ISP) guarantee:
      1. Oversample (x`oversample`) so the per-sample peak approximates the true (continuous) peak.
      2. Forward-looking peak envelope: env[i] = max(peak[i : i+lookahead]) — a pure look-ahead
         window, so gain reduction lands BEFORE the peak it must tame.
      3. required gain = min(1, ceiling/env); smooth with instant attack / one-pole release.
      4. Apply the gain IN THE OVERSAMPLED DOMAIN, then downsample the signal. Because every
         oversampled output sample is <= ceiling and the smoothed gain is slow-moving, the
         downsampled signal's own ISPs stay <= ceiling. (The previous version decimated the
         GAIN with resample_poly, whose group delay made the reduction arrive after the peak.)

    The release one-pole runs at base rate (on a block-min-reduced requirement) so the cost is
    O(n), not O(n*oversample) — the per-sample recursion is the limiter's serial hot path.
    """
    ceiling = 10 ** (ceiling_db / 20)
    x2 = as_2d(x)
    n, ch = x2.shape

    os = np.stack([resample_poly(x2[:, c], oversample, 1) for c in range(ch)], axis=-1)
    n_os = os.shape[0]
    peak_os = np.max(np.abs(os), axis=1)
    tp_in_db = 20 * np.log10(peak_os.max() + 1e-20)

    # forward look-ahead window [i, i+la): pad the tail, take a sliding max, keep n_os samples.
    la = max(1, int(lookahead_ms * 1e-3 * sr * oversample))
    padded = np.concatenate([peak_os, np.full(la, peak_os[-1])])
    env = maximum_filter1d(padded, size=la, origin=-(la // 2))[:n_os]
    req_os = np.minimum(1.0, ceiling / (env + 1e-20))

    # reduce the requirement to base rate by block-MIN (never miss a peak within a block)
    nb = n_os // oversample
    req_base = req_os[: nb * oversample].reshape(nb, oversample).min(axis=1)
    if nb < n:
        req_base = np.concatenate([req_base, np.full(n - nb, req_base[-1] if nb else 1.0)])
    req_base = req_base[:n]

    # instant attack / one-pole release at base rate
    rel = np.exp(-1.0 / max(1.0, release_ms * 1e-3 * sr))
    g_base = np.empty(n)
    cur = 1.0
    for i in range(n):
        r = req_base[i]
        cur = r if r < cur else rel * cur + (1.0 - rel) * r
        g_base[i] = cur

    # upsample the (smooth) gain to the oversampled grid, apply, then downsample the signal
    g_os = np.interp(np.arange(n_os) / oversample, np.arange(n), g_base)
    y_os = os * g_os[:, None]
    y = np.stack([resample_poly(y_os[:, c], 1, oversample)[:n] for c in range(ch)], axis=-1)
    # defensive net: the downsampler can ring ~0.01 dB; a final clip costs one vector op and
    # guards edge cases the look-ahead math doesn't bound (review, Low).
    y = np.clip(y, -ceiling, ceiling)
    return (y[:, 0] if x.ndim == 1 else y), tp_in_db
