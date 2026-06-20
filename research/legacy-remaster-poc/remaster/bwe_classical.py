"""Classical bandwidth extension — the faithful baseline for the bake-off.

Approach: nonlinear harmonic synthesis ("exciter as BWE"). We high-pass the band just
below the estimated rolloff, push it through a saturating nonlinearity (which generates
harmonics that extend above the rolloff), keep only the *new* content above the rolloff,
shape it with a downward tilt so it decays naturally, level-match, and mix back in.

The synthesized HF is generated deterministically from the program's existing content
(correlated with the signal, NOT hallucinated like a generative model) — so it is the
safe/faithful reference against which the learned models (AERO/FlashSR) are judged. It
synthesizes plausible HF; it does not *recover* the true lost detail the way a trained
model can -- that gap is the point of the bake-off.
"""
from __future__ import annotations

import numpy as np
from scipy.signal import resample_poly

from . import dsp
from .audioio import as_2d

_OVERSAMPLE = 4  # oversample factor around the nonlinearity to suppress aliasing (Part E.5)


def _excite_channel(
    ch: np.ndarray,
    sr: int,
    rolloff: float,
    drive: float,
    mix_db: float,
    tilt_db_per_oct: float,
) -> np.ndarray:
    nyq = sr / 2.0
    if rolloff >= nyq * 0.95:
        return ch  # already full-band, nothing to extend

    src = dsp.highpass(ch, max(500.0, rolloff * 0.5), sr, order=4)
    # Harmonic generator, run at _OVERSAMPLE x to keep its harmonics below the (raised)
    # Nyquist so they don't alias; the downsampler's anti-alias LPF then discards everything
    # above the base Nyquist. tanh -> odd harmonics; x**2 -> even harmonics (its DC offset is
    # removed by the high-pass below). (Earlier this used sign(x)*x**2, which is ODD, not even.)
    src_os = resample_poly(src, _OVERSAMPLE, 1)
    exc_os = np.tanh(drive * src_os) + 0.3 * (src_os ** 2)
    exc = resample_poly(exc_os, 1, _OVERSAMPLE)[: len(src)]
    exc = dsp.highpass(exc, rolloff, sr, order=6)  # keep only the synthesized HF; also drops x**2 DC

    # spectral tilt: decay the synthesized band above the rolloff
    f, _ = dsp.ltas(exc, sr, 4096, 1024)
    octv = np.log2(np.maximum(f, rolloff) / rolloff)
    tilt = 10 ** ((tilt_db_per_oct * octv) / 20.0)
    exc = _apply_tilt(exc, sr, tilt)

    # level-match the excitation to a fraction of the source band energy
    src_rms = np.sqrt(np.mean(src ** 2)) + 1e-20
    exc_rms = np.sqrt(np.mean(exc ** 2)) + 1e-20
    exc *= (src_rms / exc_rms) * (10 ** (mix_db / 20))
    return ch + exc


def _apply_tilt(x: np.ndarray, sr: int, gain_curve: np.ndarray, n_fft: int = 4096) -> np.ndarray:
    hop = n_fft // 4
    X = dsp.stft(x, n_fft, hop)
    return dsp.istft(X * gain_curve[None, :], n_fft, hop, length=len(x))


def extend_bandwidth(
    x: np.ndarray,
    sr: int,
    rolloff_hz: float | None = None,
    drive: float = 2.5,
    mix_db: float = -3.0,
    tilt_db_per_oct: float = -6.0,
) -> tuple[np.ndarray, float]:
    """Extend HF via harmonic synthesis. Returns (extended, rolloff_used_hz)."""
    x2 = as_2d(x)
    rolloff = rolloff_hz if rolloff_hz is not None else dsp.estimate_rolloff(x2[:, 0], sr)
    out = np.empty_like(x2)
    for c in range(x2.shape[1]):
        out[:, c] = _excite_channel(x2[:, c], sr, rolloff, drive, mix_db, tilt_db_per_oct)
    return (out[:, 0] if x.ndim == 1 else out), rolloff
