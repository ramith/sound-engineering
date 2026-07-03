"""Audio I/O helpers — load to float, save, channel utilities.

Conventions used throughout the POC:
- Audio arrays are float64 for processing accuracy, shape (n,) for mono or
  (n, ch) for multi-channel. We cast to float32 only at save time.
- Sample rate is carried alongside as an int.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly


def _decode_external(path: str) -> tuple[np.ndarray, int]:
    """Decode formats libsndfile can't (m4a/aac/mp4, some mp3s) via ffmpeg, then afconvert.

    Decodes to a temp 32-bit-float WAV at the source sample rate, reads it back. ffmpeg
    is preferred (universal); afconvert is the macOS-native fallback (always present)."""
    with tempfile.TemporaryDirectory() as td:
        tmp = os.path.join(td, "decoded.wav")
        if shutil.which("ffmpeg"):
            cmd = ["ffmpeg", "-v", "error", "-y", "-i", path, "-c:a", "pcm_f32le", tmp]
        elif shutil.which("afconvert"):
            cmd = ["afconvert", path, tmp, "-d", "LEF32", "-f", "WAVE"]
        else:
            raise RuntimeError(f"No external decoder (ffmpeg/afconvert) found to read: {path}")
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            raise RuntimeError(f"Decode failed for {path}:\n{proc.stderr.strip()}")
        return sf.read(tmp, dtype="float64", always_2d=False)


def load(path: str, target_sr: int | None = None) -> tuple[np.ndarray, int]:
    """Load an audio file to float64. Returns (data, sr).

    data is (n,) mono or (n, ch). Handles wav/flac/ogg/mp3 via libsndfile and
    m4a/aac/mp4 (and any libsndfile failure) via ffmpeg/afconvert. Resamples if target_sr set.
    """
    try:
        data, sr = sf.read(path, dtype="float64", always_2d=False)
    except Exception:
        data, sr = _decode_external(path)
    if target_sr is not None and sr != target_sr:
        data = resample(data, sr, target_sr)
        sr = target_sr
    return data, sr


def save(path: str, data: np.ndarray, sr: int, subtype: str = "PCM_24") -> None:
    """Save float audio. Accepts (n,) or (n, ch). Clipped to [-1, 1] defensively.
    Creates the parent directory if needed."""
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    out = np.clip(np.asarray(data, dtype=np.float64), -1.0, 1.0).astype(np.float32)
    sf.write(path, out, sr, subtype=subtype)


def resample(data: np.ndarray, sr_in: int, sr_out: int) -> np.ndarray:
    """Polyphase resample, per channel."""
    if sr_in == sr_out:
        return data
    from math import gcd

    g = gcd(sr_in, sr_out)
    up, down = sr_out // g, sr_in // g
    if data.ndim == 1:
        return resample_poly(data, up, down)
    return np.stack([resample_poly(data[:, c], up, down) for c in range(data.shape[1])], axis=-1)


def to_mono(data: np.ndarray) -> np.ndarray:
    """Average channels to mono (n,)."""
    if data.ndim == 1:
        return data
    return data.mean(axis=1)


def is_stereo(data: np.ndarray) -> bool:
    return data.ndim == 2 and data.shape[1] == 2


def as_2d(data: np.ndarray) -> np.ndarray:
    """Return (n, ch); mono -> (n, 1)."""
    return data[:, None] if data.ndim == 1 else data


def rms_db(x: np.ndarray) -> float:
    """Broadband RMS in dBFS."""
    r = np.sqrt(np.mean(np.square(x))) + 1e-20
    return 20.0 * np.log10(r)
