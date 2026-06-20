"""Synthetic test material: a 'modern' full-band reference and a 'legacy'-degraded version.

Used to validate the pipeline offline with ground truth — the remaster should measurably
move the legacy signal back toward the modern reference (HF energy up, noise floor down,
LUFS to target, LTAS distance to reference down). Real-world validation uses the founder's
own mp3/m4a tracks via the CLI; this is the deterministic regression fixture.
"""
from __future__ import annotations

import numpy as np

from . import dsp


def _harmonic_tone(
    f0: float, sr: int, n: int, n_harm: int, decay: float, rng: np.random.Generator
) -> np.ndarray:
    """A pitched tone: harmonic series with 1/k^decay rolloff and small random phases."""
    t = np.arange(n) / sr
    out = np.zeros(n)
    for k in range(1, n_harm + 1):
        fk = f0 * k
        if fk >= sr / 2:
            break
        out += (1.0 / k**decay) * np.sin(2 * np.pi * fk * t + rng.uniform(0, 2 * np.pi))
    return out


def make_modern_reference(sr: int = 44100, dur: float = 8.0, seed: int = 7) -> np.ndarray:
    """A bright, full-band stereo musical signal (energy out to ~18 kHz). Returns (n, 2)."""
    rng = np.random.default_rng(seed)
    n = int(sr * dur)
    t = np.arange(n) / sr

    # An A-major chord (A2, C#4, E4, A4) as harmonic tones.
    chord = sum(
        _harmonic_tone(f0, sr, n, n_harm=24, decay=0.9, rng=rng)
        for f0 in (110.0, 277.18, 329.63, 440.0)
    )

    # A "hi-hat" — high-passed noise bursts every half second for genuine HF/air content.
    hat = rng.standard_normal(n)
    hat = dsp.highpass(hat, 6000.0, sr, order=4)
    env = np.zeros(n)
    step = int(sr * 0.5)
    for s in range(0, n, step):
        seg = np.exp(-np.arange(min(step, n - s)) / (0.04 * sr))
        env[s : s + len(seg)] = seg
    hat *= env * 0.5

    # Deep bass fundamental for "weight".
    bass = 0.6 * np.sin(2 * np.pi * 55.0 * t)

    mono = 0.5 * chord + hat + bass
    mono /= np.max(np.abs(mono)) + 1e-9

    # Mild stereo: decorrelated copy panned via a tiny delay.
    delay = int(sr * 0.0007)
    right = np.concatenate([np.zeros(delay), mono[:-delay]]) if delay else mono
    stereo = np.stack([mono, 0.85 * mono + 0.15 * right], axis=-1)
    return 0.7 * stereo / (np.max(np.abs(stereo)) + 1e-9)


def degrade_to_legacy(
    modern: np.ndarray,
    sr: int = 44100,
    rolloff_hz: float = 8000.0,
    bass_cut_hz: float = 130.0,
    hiss_db: float = -42.0,
    lead_noise_s: float = 1.0,
    attenuate_db: float = -8.0,
    seed: int = 11,
) -> np.ndarray:
    """Simulate a legacy recording: HF rolloff + thin bass + hiss + mono + quiet, with a
    leading noise-only segment for the de-hiss profile. Returns mono (n,)."""
    rng = np.random.default_rng(seed)
    mono = modern.mean(axis=1) if modern.ndim == 2 else modern.copy()

    mono = dsp.lowpass(mono, rolloff_hz, sr, order=8)          # kill the air
    mono = dsp.highpass(mono, bass_cut_hz, sr, order=2)        # thin the bass

    hiss_amp = 10 ** (hiss_db / 20)
    mono = mono + hiss_amp * rng.standard_normal(len(mono))    # broadband hiss
    mono *= 10 ** (attenuate_db / 20)                          # quiet old master

    lead = hiss_amp * rng.standard_normal(int(lead_noise_s * sr))
    return np.concatenate([lead, mono])
