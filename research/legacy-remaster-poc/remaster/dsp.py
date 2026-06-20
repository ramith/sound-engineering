"""Shared DSP primitives: self-contained STFT/ISTFT (COLA), LTAS, log smoothing, filters.

We roll our own STFT to avoid scipy's churning stft/istft -> ShortTimeFFT API
deprecations, and so the WOLA reconstruction is explicit and auditable.
"""
from __future__ import annotations

import numpy as np
from scipy.signal import butter, sosfiltfilt


# ----------------------------------------------------------------------------- windows
def hann(n_fft: int) -> np.ndarray:
    """Periodic Hann (DFT-even), the right choice for OLA/WOLA."""
    return np.hanning(n_fft + 1)[:-1].astype(np.float64)


# ----------------------------------------------------------------------------- STFT
def stft(x: np.ndarray, n_fft: int = 2048, hop: int = 512, window: np.ndarray | None = None) -> np.ndarray:
    """Real STFT. Returns complex array [n_frames, n_bins]. Center-padded (reflect)."""
    if window is None:
        window = hann(n_fft)
    x = np.asarray(x, dtype=np.float64)
    if x.ndim != 1:
        raise ValueError(f"stft expects a mono 1-D signal; got shape {x.shape}. Reduce channels first.")
    pad = n_fft // 2
    xp = np.pad(x, pad, mode="reflect")
    n_frames = 1 + max(0, (len(xp) - n_fft) // hop)
    frames = np.lib.stride_tricks.sliding_window_view(xp, n_fft)[::hop][:n_frames]
    return np.fft.rfft(frames * window, n=n_fft, axis=1)


def istft(
    X: np.ndarray,
    n_fft: int = 2048,
    hop: int = 512,
    window: np.ndarray | None = None,
    length: int | None = None,
) -> np.ndarray:
    """Inverse STFT with windowed overlap-add (WOLA), normalized by the squared-window sum.

    Reconstruction is exact in the interior for signals spanning several hops. For signals
    shorter than ~3*hop the edge window-sum is tiny and the 1e-8 floor would amplify the tail;
    callers process full-length signals (de-hiss guards inputs shorter than one frame)."""
    if window is None:
        window = hann(n_fft)
    frames = np.fft.irfft(X, n=n_fft, axis=1)
    n_frames = frames.shape[0]
    out_len = n_fft + hop * (n_frames - 1)
    out = np.zeros(out_len)
    wsum = np.zeros(out_len)
    w2 = window * window
    for i in range(n_frames):
        s = i * hop
        out[s : s + n_fft] += frames[i] * window
        wsum[s : s + n_fft] += w2
    wsum = np.maximum(wsum, 1e-8)
    out /= wsum
    pad = n_fft // 2
    out = out[pad:]
    if length is not None:
        out = out[:length] if len(out) >= length else np.pad(out, (0, length - len(out)))
    return out


# ----------------------------------------------------------------------------- spectra
def rfftfreqs(n_fft: int, sr: int) -> np.ndarray:
    return np.fft.rfftfreq(n_fft, d=1.0 / sr)


def ltas(x: np.ndarray, sr: int, n_fft: int = 4096, hop: int = 1024) -> tuple[np.ndarray, np.ndarray]:
    """Long-term average spectrum as mean per-bin POWER. Returns (freqs, power).

    Tonal balance is a broadband property, so multichannel input is averaged to mono."""
    if np.asarray(x).ndim > 1:
        x = np.asarray(x, dtype=np.float64).mean(axis=1)
    X = stft(x, n_fft, hop)
    power = np.mean(np.abs(X) ** 2, axis=0)
    return rfftfreqs(n_fft, sr), power


def smooth_log(freqs: np.ndarray, spec: np.ndarray, frac: float = 1.0 / 3.0) -> np.ndarray:
    """Fractional-octave smoothing of a spectrum (averaging window centered per bin)."""
    out = np.empty_like(spec)
    half = 2.0 ** (frac / 2.0)
    for i, f in enumerate(freqs):
        if f <= 0:
            out[i] = spec[i]
            continue
        lo, hi = f / half, f * half
        m = (freqs >= lo) & (freqs <= hi)
        out[i] = spec[m].mean() if m.any() else spec[i]
    return out


def hf_energy_db(x: np.ndarray, sr: int, fmin: float, fmax: float, n_fft: int = 4096) -> float:
    """Energy in [fmin, fmax] relative to full-band, in dB. Useful to quantify 'air'."""
    f, p = ltas(x, sr, n_fft, n_fft // 4)
    band = (f >= fmin) & (f <= fmax)
    e_band = p[band].sum() + 1e-20
    e_full = p.sum() + 1e-20
    return 10.0 * np.log10(e_band / e_full)


def estimate_rolloff(x: np.ndarray, sr: int, drop_db: float = 25.0, n_fft: int = 4096) -> float:
    """Estimate HF rolloff: highest freq whose smoothed level is within drop_db of the
    mid-band (200 Hz-2 kHz) level. A crude but robust proxy for 'where the highs die'."""
    f, p = ltas(x, sr, n_fft, n_fft // 4)
    ps = smooth_log(f, p, 1.0 / 3.0)
    ps_db = 10.0 * np.log10(ps + 1e-20)
    mid = (f >= 200) & (f <= 2000)
    ref_db = np.median(ps_db[mid]) if mid.any() else ps_db.max()
    above = f > 2000
    ok = above & (ps_db >= ref_db - drop_db)
    return float(f[ok].max()) if ok.any() else float(f[-1])


# ----------------------------------------------------------------------------- filters
def butter_sos(cutoff, sr: int, btype: str, order: int = 4):
    return butter(order, cutoff, btype=btype, fs=sr, output="sos")


def highpass(x: np.ndarray, fc: float, sr: int, order: int = 4) -> np.ndarray:
    return sosfiltfilt(butter_sos(fc, sr, "highpass", order), x)


def lowpass(x: np.ndarray, fc: float, sr: int, order: int = 4) -> np.ndarray:
    return sosfiltfilt(butter_sos(fc, sr, "lowpass", order), x)
