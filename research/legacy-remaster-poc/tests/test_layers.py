import numpy as np

from remaster import bwe_classical, dsp, loudness, match_eq, width


def _tone(f, sr, n, amp=0.3):
    return amp * np.sin(2 * np.pi * f * np.arange(n) / sr)


def test_dehiss_reduces_noise_floor_with_explicit_segment():
    from remaster.dehiss import dehiss

    sr = 44100
    rng = np.random.default_rng(3)
    lead = 0.01 * rng.standard_normal(int(0.8 * sr))            # noise-only lead
    body = _tone(440, sr, sr) + 0.01 * rng.standard_normal(sr)  # tone + same hiss
    x = np.concatenate([lead, body])

    y = dehiss(x, sr, noise_start=0.0, noise_dur=0.7)

    # noise floor in the lead region should drop substantially
    in_floor = np.sqrt(np.mean(x[: int(0.7 * sr)] ** 2))
    out_floor = np.sqrt(np.mean(y[: int(0.7 * sr)] ** 2))
    assert out_floor < 0.5 * in_floor, "de-hiss did not reduce the noise floor"

    # the 440 Hz tone should survive (bin energy preserved within ~3 dB)
    f, p_in = dsp.ltas(body, sr, 4096, 1024)
    _, p_out = dsp.ltas(y[len(lead):], sr, 4096, 1024)
    k = int(round(440 / (sr / 4096)))
    tone_in = 10 * np.log10(p_in[k] + 1e-20)
    tone_out = 10 * np.log10(p_out[k] + 1e-20)
    assert abs(tone_out - tone_in) < 3.0, f"tone over-attenuated: {tone_in:.1f} -> {tone_out:.1f} dB"


def test_normalize_lufs_hits_target():
    sr = 44100
    rng = np.random.default_rng(4)
    x = 0.1 * rng.standard_normal(sr * 3)  # 3 s, enough for gated integrated loudness
    y, measured, gain = loudness.normalize_lufs(x, sr, target_lufs=-14.0)
    assert np.isfinite(measured)
    out_lufs = loudness.integrated_lufs(y, sr)
    assert abs(out_lufs - (-14.0)) < 0.5, f"LUFS target missed: {out_lufs}"


def test_true_peak_limit_respects_ceiling():
    sr = 44100
    x = 0.99 * np.sin(2 * np.pi * 997 * np.arange(sr) / sr)  # near full-scale, inter-sample peaks
    y, tp_in = loudness.true_peak_limit(x, sr, ceiling_db=-1.0)
    from scipy.signal import resample_poly

    os = resample_poly(y, 4, 1)
    tp_out_db = 20 * np.log10(np.max(np.abs(os)) + 1e-20)
    assert tp_out_db <= -1.0 + 0.5, f"limiter exceeded ceiling: {tp_out_db:.2f} dBTP"


def test_pseudo_stereo_is_mono_compatible():
    sr = 44100
    rng = np.random.default_rng(5)
    mono = 0.2 * rng.standard_normal(sr)
    st = width.mono_to_pseudo_stereo(mono, sr, width=0.4)
    assert st.shape == (sr, 2)
    dev = width.mono_sum_deviation_db(st, mono)
    assert abs(dev) < 1.0, f"mono sum not preserved: {dev:.2f} dB"


def test_widen_stereo_preserves_mono_sum():
    rng = np.random.default_rng(6)
    st = 0.2 * rng.standard_normal((44100, 2))
    mono_before = st.mean(axis=1)
    wide = width.widen_stereo(st, amount=0.5)
    dev = width.mono_sum_deviation_db(wide, mono_before)
    assert abs(dev) < 1.0, f"widening changed the mono sum: {dev:.2f} dB"


def test_match_eq_reduces_ltas_distance_to_reference():
    sr = 44100
    rng = np.random.default_rng(7)
    ref = rng.standard_normal(sr * 2)
    target = dsp.lowpass(ref.copy(), 6000.0, sr, order=8)  # dull version

    def ltas_dist(a, b):
        f, pa = dsp.ltas(a, sr, 4096, 1024)
        _, pb = dsp.ltas(b, sr, 4096, 1024)
        da = 10 * np.log10(dsp.smooth_log(f, pa, 1 / 3) + 1e-20)
        db = 10 * np.log10(dsp.smooth_log(f, pb, 1 / 3) + 1e-20)
        band = f >= 100
        return np.mean(np.abs(da[band] - db[band]))

    before = ltas_dist(target, ref)
    eqd, _ = match_eq.match_eq(target, ref, sr)
    after = ltas_dist(eqd, ref)
    assert after < before, f"match-EQ did not move toward reference: {before:.2f} -> {after:.2f}"


def test_bwe_adds_hf_energy():
    sr = 44100
    rng = np.random.default_rng(8)
    full = rng.standard_normal(sr)
    dull = dsp.lowpass(full, 8000.0, sr, order=8)
    bright, rolloff = bwe_classical.extend_bandwidth(dull, sr)
    hf_before = dsp.hf_energy_db(dull, sr, 10000, sr / 2)
    hf_after = dsp.hf_energy_db(bright, sr, 10000, sr / 2)
    assert hf_after > hf_before + 1.0, f"BWE added no HF: {hf_before:.1f} -> {hf_after:.1f} dB"
    assert 6000 < rolloff < 11000
