"""De-hiss: log-MMSE log-spectral-amplitude (LSA) estimator with decision-directed
a-priori SNR (Ephraim & Malah, IEEE TASSP 1985 = the log-amplitude/LSA estimator;
the 1984 paper is the non-log MMSE-STSA; Cappe 1994 on musical-noise removal).

Why this and not spectral subtraction: the log-MMSE gain is a smooth, low-variance
function of SNR, and the decision-directed a-priori SNR estimate uses the *previous*
clean frame -> the gain trajectory is smooth across time, which is what suppresses the
warbling "musical noise" that plagues spectral subtraction on music.

Noise PSD is taken from an explicit noise-only segment when available (best), else a
low-percentile-over-time estimate (a simple minimum-statistics proxy).
"""
from __future__ import annotations

import logging

import numpy as np
from scipy.special import exp1  # exponential integral E1

from . import dsp
from .audioio import as_2d

log = logging.getLogger(__name__)


def estimate_noise_psd(
    x: np.ndarray,
    sr: int,
    n_fft: int,
    hop: int,
    noise_start: float | None = None,
    noise_dur: float | None = None,
    percentile: float = 10.0,
) -> np.ndarray:
    """Per-bin noise power estimate.

    If (noise_start, noise_dur) given -> mean power over that explicit noise-only segment.
    Else -> `percentile`-th percentile of per-bin power across time (minimum-statistics proxy).

    Note: the blind percentile path is a fallback. It assumes each bin drops to noise-only
    at least `percentile`% of the time; for dense/sustained music it overestimates the floor
    at busy bins (over-subtraction). Prefer an explicit noise segment; Martin (2001) minimum
    statistics over a sliding window would be the principled blind estimator (future work).
    """
    if noise_start is not None and noise_dur is not None:
        a = max(0, int(noise_start * sr))
        b = min(len(x), int((noise_start + noise_dur) * sr))
        seg = x[a:b]
        if len(seg) >= n_fft:
            X = dsp.stft(seg, n_fft, hop)
            return np.mean(np.abs(X) ** 2, axis=0)
        log.warning(
            "noise segment [%.2f, %.2f]s is shorter than one analysis frame; "
            "falling back to blind percentile estimate.", noise_start, noise_start + (noise_dur or 0),
        )
    X = dsp.stft(x, n_fft, hop)
    return np.percentile(np.abs(X) ** 2, percentile, axis=0)


def _logmmse_gain(
    noisy_power: np.ndarray, noise_psd: np.ndarray, alpha: float, gain_floor: float
) -> np.ndarray:
    """Compute the per-frame log-MMSE gain across all frames (vectorized over time)."""
    n_frames, _ = noisy_power.shape
    gain = np.empty_like(noisy_power)
    # xi_min and gain_floor are practical engineering tunings (a spectral floor / a-priori
    # SNR floor), NOT values from Ephraim & Malah; they trade residual hiss vs. musical noise.
    xi_min = 10 ** (-25 / 10)  # a-priori SNR floor (~ -25 dB)
    prev_clean_power = noise_psd.copy()  # init clean estimate at the noise floor
    for m in range(n_frames):
        gamma = noisy_power[m] / (noise_psd + 1e-20)            # a-posteriori SNR
        ml = np.maximum(gamma - 1.0, 0.0)                       # ML a-priori SNR
        xi = alpha * (prev_clean_power / (noise_psd + 1e-20)) + (1.0 - alpha) * ml
        xi = np.maximum(xi, xi_min)
        v = np.clip(xi / (1.0 + xi) * gamma, 1e-6, 500.0)
        g = (xi / (1.0 + xi)) * np.exp(0.5 * exp1(v))           # log-MMSE LSA gain
        # C-1: the LSA gain is a SUPPRESSION function — clamp to [floor, 1]. Without the
        # upper clamp, frames with gamma < 1 (power below the noise estimate) get amplified
        # (G can exceed 1), and the decision-directed recursion then snowballs. Clamp first,
        # THEN feed the DD estimate so prev_clean_power can't be inflated by a >1 gain.
        g = np.clip(g, gain_floor, 1.0)
        gain[m] = g
        prev_clean_power = (g ** 2) * noisy_power[m]            # feeds next frame's DD estimate
    return gain


def dehiss(
    x: np.ndarray,
    sr: int,
    n_fft: int = 2048,
    hop: int = 512,
    alpha: float = 0.95,
    noise_overestimate: float = 1.0,
    gain_floor_db: float = -18.0,
    noise_start: float | None = None,
    noise_dur: float | None = None,
) -> np.ndarray:
    """Apply log-MMSE de-hiss. Handles mono (n,) or multi-channel (n, ch).

    alpha               decision-directed smoothing. The canonical Ephraim-Malah/Cappe value
                        is ~0.98; we default to 0.95 (a practical music tuning: less transient
                        smear, slightly more residual). Range 0.92-0.97.
    noise_overestimate  scale the noise PSD (>1 = more aggressive, risks musical noise)
    gain_floor_db       spectral floor (practical tuning, not from E&M); leaves a quiet
                        stationary residual instead of holes
    noise_start/dur     explicit noise-only segment (seconds); else low-percentile estimate
    """
    x2 = as_2d(x)
    if x2.shape[0] < n_fft:
        log.warning("signal shorter than one analysis frame (%d < %d); skipping de-hiss", x2.shape[0], n_fft)
        return x
    gain_floor = 10 ** (gain_floor_db / 20)
    out = np.empty_like(x2)
    for c in range(x2.shape[1]):
        ch = x2[:, c]
        noise_psd = noise_overestimate * estimate_noise_psd(ch, sr, n_fft, hop, noise_start, noise_dur)
        noise_floor_db = 10 * np.log10(np.mean(noise_psd) + 1e-20)
        X = dsp.stft(ch, n_fft, hop)
        n_frames = X.shape[0]
        log.debug(
            "dehiss ch%d: %d frames, est. noise floor %.1f dB (%s)",
            c, n_frames, noise_floor_db,
            "explicit segment" if noise_start is not None else "blind percentile",
        )
        gain = _logmmse_gain(np.abs(X) ** 2, noise_psd, alpha, gain_floor)
        out[:, c] = dsp.istft(X * gain, n_fft, hop, length=len(ch))
    return out[:, 0] if x.ndim == 1 else out
