"""Verification & measurement: spectrograms, LTAS overlay, spectral-kurtosis musical-noise
proxy, HF-energy delta, and an RTF timer. Plots are written to PNG (Claude can't listen,
so the founder does the A/B; these make the *measurable* claims checkable offline)."""
from __future__ import annotations

import time
from contextlib import contextmanager

import matplotlib

matplotlib.use("Agg")  # headless
import matplotlib.pyplot as plt
import numpy as np
from scipy.stats import kurtosis

from . import dsp
from .audioio import to_mono


# ------------------------------------------------------------------- timing
class Timer:
    """Accumulates named wall-clock durations for an RTF report."""

    def __init__(self) -> None:
        self.times: dict[str, float] = {}

    @contextmanager
    def stage(self, name: str):
        t0 = time.perf_counter()
        yield
        self.times[name] = self.times.get(name, 0.0) + (time.perf_counter() - t0)

    def total(self) -> float:
        return sum(self.times.values())

    def report(self, audio_seconds: float) -> str:
        lines = ["  layer timings (s) and share of real-time:"]
        for k, v in self.times.items():
            lines.append(f"    {k:<16} {v:8.3f}s   RTF={v / audio_seconds:6.4f}")
        tot = self.total()
        lines.append(f"    {'TOTAL':<16} {tot:8.3f}s   RTF={tot / audio_seconds:6.4f}")
        return "\n".join(lines)


# ------------------------------------------------------------------- metrics
def spectral_kurtosis(x: np.ndarray, sr: int, n_fft: int = 2048) -> float:
    """Mean temporal kurtosis of per-bin magnitude. Elevated vs source => musical noise
    (isolated, bursty time-frequency peaks). Arras et al. 2021 musical-noise measure idea.

    Always measured at a FIXED n_fft (2048) regardless of the resolution the processing used,
    so numbers are comparable across methods. It is a PROXY, not proof — two benign things also
    raise it: (1) re-adding genuine HF transients (BWE), and (2) de-hissing — stationary hiss is
    low-kurtosis and fills temporal gaps, so removing it lets the signal's real transient
    structure re-emerge and the metric rises. (Measured on the fixture: de-hiss takes 9 -> 31,
    while the bright modern *reference* sits at ~57.) Treat large jumps as "go listen.\""""
    X = np.abs(dsp.stft(to_mono(x), n_fft, n_fft // 4))
    k = kurtosis(X, axis=0, fisher=True, bias=False)  # per-bin over time
    return float(np.nanmean(k))


def hf_energy_db(x: np.ndarray, sr: int, fmin: float = 10000.0, fmax: float | None = None) -> float:
    fmax = fmax if fmax is not None else sr / 2.0
    return dsp.hf_energy_db(to_mono(x), sr, fmin, fmax)


# ------------------------------------------------------------------- plots
def plot_ltas(signals: dict[str, np.ndarray], sr: int, path: str, title: str = "LTAS") -> None:
    plt.figure(figsize=(9, 5))
    for name, x in signals.items():
        f, p = dsp.ltas(to_mono(x), sr, 4096, 1024)
        ps = dsp.smooth_log(f, p, 1.0 / 6.0)
        plt.semilogx(f[1:], 10 * np.log10(ps[1:] + 1e-20), label=name, linewidth=1.6)
    plt.xlim(20, sr / 2)
    plt.xlabel("Frequency (Hz)")
    plt.ylabel("Power (dB, arb.)")
    plt.title(title)
    plt.grid(True, which="both", alpha=0.3)
    plt.legend()
    plt.tight_layout()
    plt.savefig(path, dpi=110)
    plt.close()


def plot_spectrogram(x: np.ndarray, sr: int, path: str, title: str = "Spectrogram") -> None:
    X = dsp.stft(to_mono(x), 2048, 512)
    S = 20 * np.log10(np.abs(X).T + 1e-6)
    plt.figure(figsize=(9, 5))
    extent = [0, len(to_mono(x)) / sr, 0, sr / 2]
    plt.imshow(S, origin="lower", aspect="auto", extent=extent, vmin=S.max() - 90, vmax=S.max(), cmap="magma")
    plt.xlabel("Time (s)")
    plt.ylabel("Frequency (Hz)")
    plt.title(title)
    plt.colorbar(label="dB")
    plt.tight_layout()
    plt.savefig(path, dpi=110)
    plt.close()


def plot_eq_curve(freqs: np.ndarray, gain_db: np.ndarray, path: str, title: str = "Match-EQ curve") -> None:
    plt.figure(figsize=(9, 4))
    plt.semilogx(freqs[1:], gain_db[1:], linewidth=1.8)
    plt.axhline(0, color="k", alpha=0.4)
    plt.xlim(20, freqs[-1])
    plt.xlabel("Frequency (Hz)")
    plt.ylabel("Gain (dB)")
    plt.title(title)
    plt.grid(True, which="both", alpha=0.3)
    plt.tight_layout()
    plt.savefig(path, dpi=110)
    plt.close()
