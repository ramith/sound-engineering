import numpy as np

from remaster import dsp


def test_stft_istft_roundtrip_interior():
    rng = np.random.default_rng(0)
    x = rng.standard_normal(44100)  # 1 s
    X = dsp.stft(x, 2048, 512)
    y = dsp.istft(X, 2048, 512, length=len(x))
    # interior reconstruction (skip the first/last frame where windowing tapers)
    a, b = 4096, len(x) - 4096
    err = np.sqrt(np.mean((y[a:b] - x[a:b]) ** 2)) / (np.sqrt(np.mean(x[a:b] ** 2)) + 1e-12)
    assert err < 1e-3, f"WOLA reconstruction relative error too high: {err}"


def test_stft_shapes():
    x = np.zeros(10000)
    X = dsp.stft(x, 1024, 256)
    assert X.shape[1] == 1024 // 2 + 1


def test_estimate_rolloff_on_lowpassed_signal():
    sr = 44100
    rng = np.random.default_rng(1)
    x = rng.standard_normal(sr * 2)
    x_lp = dsp.lowpass(x, 8000.0, sr, order=8)
    roll = dsp.estimate_rolloff(x_lp, sr)
    assert 6000 < roll < 11000, f"rolloff estimate off: {roll}"


def test_hf_energy_increases_with_brightness():
    sr = 44100
    rng = np.random.default_rng(2)
    white = rng.standard_normal(sr)
    dark = dsp.lowpass(white, 5000.0, sr, order=8)
    assert dsp.hf_energy_db(white, sr, 10000, sr / 2) > dsp.hf_energy_db(dark, sr, 10000, sr / 2)
