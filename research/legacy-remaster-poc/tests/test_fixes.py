"""Regression tests for the review fixes (C-1, C-2/M-5, H-2, H-3)."""
import numpy as np
from scipy.signal import resample_poly

from remaster import bwe_classical, dehiss, dsp, loudness, match_eq, pipeline, synth


# --- C-1: log-MMSE gain must never exceed unity (it's a suppression function) -----------
def test_logmmse_gain_never_exceeds_unity():
    rng = np.random.default_rng(0)
    noisy_power = rng.random((200, 100)) * 0.5  # most frames below the noise floor -> gamma < 1
    noise_psd = np.ones(100)
    floor = 10 ** (-18 / 20)
    g = dehiss._logmmse_gain(noisy_power, noise_psd, alpha=0.95, gain_floor=floor)
    assert g.max() <= 1.0 + 1e-9, f"gain exceeded unity (would amplify noise): {g.max()}"
    assert g.min() >= floor - 1e-9


def test_dehiss_does_not_amplify_pure_noise():
    sr = 44100
    rng = np.random.default_rng(1)
    noise = 0.02 * rng.standard_normal(sr)
    y = dehiss.dehiss(noise, sr, noise_start=0.0, noise_dur=0.5)
    assert np.sqrt(np.mean(y ** 2)) <= np.sqrt(np.mean(noise ** 2)) + 1e-9


# --- H-2: limiter holds the true-peak ceiling on a sustained near-fullscale burst --------
def test_limiter_holds_ceiling_with_lookahead():
    sr = 44100
    x = np.zeros(sr)
    x[sr // 2 : sr // 2 + 50] = 0.99  # a burst the look-ahead must catch
    y, _ = loudness.true_peak_limit(x, sr, ceiling_db=-1.0)
    os = resample_poly(y, 8, 1)  # 8x to estimate true peak
    tp = 20 * np.log10(np.max(np.abs(os)) + 1e-20)
    assert tp <= -1.0 + 0.3, f"true-peak overshoot: {tp:.2f} dBTP"


# --- C-2/M-5: oversampling suppresses the aliased 3rd harmonic ---------------------------
def test_bwe_oversampling_suppresses_alias():
    sr = 44100
    f0 = 9000.0
    x = 0.3 * np.sin(2 * np.pi * f0 * np.arange(sr) / sr)
    y, _ = bwe_classical.extend_bandwidth(x, sr, rolloff_hz=8000.0, drive=3.0)
    f, p = dsp.ltas(y, sr, 8192, 2048)

    def band_power(center, bw=300):
        m = (f >= center - bw) & (f <= center + bw)
        return p[m].sum() + 1e-20

    harm_2nd = band_power(2 * f0)         # 18 kHz, legitimate even harmonic (kept)
    alias_3rd = band_power(sr - 3 * f0)   # 27 kHz would alias to 17.1 kHz without oversampling
    assert harm_2nd > alias_3rd, f"alias not suppressed: 2nd={harm_2nd:.2e}, alias={alias_3rd:.2e}"


# --- H-3: match-EQ correction is faded to zero above the rolloff -------------------------
def test_match_eq_taper_zeroes_above_rolloff():
    sr = 44100
    rng = np.random.default_rng(2)
    ref = rng.standard_normal(sr)
    target = dsp.lowpass(ref.copy(), 8000.0, sr, order=8)
    f, gain_db = match_eq.corrective_curve(target, ref, sr, rolloff_hz=8000.0)
    above = f >= 16000.0  # one octave above rolloff
    assert np.allclose(gain_db[above], 0.0, atol=1e-9), "match-EQ not tapered above 2x rolloff"


# --- N1: the HF taper must apply even when BWE is disabled (rolloff is detected, not from BWE) -
def test_match_eq_taper_applies_with_bwe_disabled():
    sr = 44100
    modern = synth.make_modern_reference(sr=sr, dur=3.0)
    legacy = synth.degrade_to_legacy(modern, sr=sr)
    cfg = pipeline.RemasterConfig(do_bwe=False, do_match_eq=True, noise_start=0.0, noise_dur=0.8)
    res = pipeline.remaster(legacy, sr, cfg, reference=modern)
    assert "rolloff_hz" in res.info, "rolloff should be detected even with BWE off"
    f, gain_db = res.info["eq_curve"]
    above = f >= 2 * res.info["rolloff_hz"]
    assert np.allclose(gain_db[above], 0.0, atol=1e-9), "match-EQ not tapered above rolloff when BWE disabled"


# --- M-3: pipeline input validation ------------------------------------------------------
def test_pipeline_rejects_bad_input():
    import pytest

    with pytest.raises(ValueError):
        pipeline.remaster(np.array([]), 44100)
    with pytest.raises(ValueError):
        pipeline.remaster(np.array([np.nan, 0.1, 0.2]), 44100)
    with pytest.raises(ValueError):
        pipeline.remaster(np.zeros(1000), 0)
