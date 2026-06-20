"""I/O round-trips, including the m4a/AAC decode path that exercises ffmpeg/afconvert."""
import shutil
import subprocess

import numpy as np
import pytest

from remaster import audioio


def test_wav_roundtrip(tmp_path):
    sr = 44100
    x = 0.3 * np.sin(2 * np.pi * 440 * np.arange(sr) / sr)
    p = tmp_path / "tone.wav"
    audioio.save(str(p), x, sr)
    y, sr2 = audioio.load(str(p))
    assert sr2 == sr
    assert np.corrcoef(x[:len(y)], y[:len(x)])[0, 1] > 0.999


def test_resample_changes_length_proportionally():
    sr = 48000
    x = np.sin(2 * np.pi * 1000 * np.arange(sr) / sr)
    y = audioio.resample(x, 48000, 44100)
    assert abs(len(y) / len(x) - 44100 / 48000) < 0.01


@pytest.mark.skipif(not shutil.which("ffmpeg"), reason="ffmpeg not installed")
def test_m4a_decode_roundtrip(tmp_path):
    """Encode a tone to .m4a (AAC) via ffmpeg, then confirm our loader decodes it."""
    sr = 44100
    x = 0.3 * np.sin(2 * np.pi * 440 * np.arange(sr * 2) / sr)
    wav = tmp_path / "tone.wav"
    m4a = tmp_path / "tone.m4a"
    audioio.save(str(wav), x, sr)
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", str(wav), "-c:a", "aac", "-b:a", "128k", str(m4a)],
        check=True,
    )
    y, sr2 = audioio.load(str(m4a), target_sr=sr)
    assert sr2 == sr
    assert len(y) > sr  # got real samples back
    assert np.all(np.isfinite(y))
