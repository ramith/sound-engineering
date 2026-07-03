import numpy as np

from remaster import dsp, loudness, synth
from remaster.pipeline import RemasterConfig, remaster


def test_end_to_end_remaster_on_synthetic_legacy():
    sr = 44100
    modern = synth.make_modern_reference(sr=sr, dur=6.0)
    legacy = synth.degrade_to_legacy(modern, sr=sr)

    cfg = RemasterConfig(noise_start=0.0, noise_dur=0.8, target_lufs=-14.0)
    result = remaster(legacy, sr, cfg, reference=modern)

    out = result.audio
    assert np.all(np.isfinite(out)), "output contains NaN/Inf"
    assert out.ndim == 2 and out.shape[1] == 2, "expected stereo output (pseudo-stereo)"

    # loudness hit the target
    out_lufs = loudness.integrated_lufs(out, sr)
    assert abs(out_lufs - (-14.0)) < 1.0, f"LUFS off: {out_lufs}"

    # bandwidth extension adds genuine HF: the full chain is brighter than the same chain with
    # BWE off (comparing to the raw legacy would be confounded by its broadband HISS, which
    # de-hiss correctly removes — and match-EQ no longer boosts that residual, per fix H-3).
    no_bwe_cfg = RemasterConfig(noise_start=0.0, noise_dur=0.8, do_bwe=False)
    no_bwe = remaster(legacy, sr, no_bwe_cfg, reference=modern)
    hf_no_bwe = dsp.hf_energy_db(no_bwe.audio, sr, 10000, sr / 2)
    hf_full = dsp.hf_energy_db(out, sr, 10000, sr / 2)
    assert hf_full > hf_no_bwe, f"BWE added no HF: {hf_no_bwe:.1f} -> {hf_full:.1f} dB"

    # mono-compatible and timed
    assert abs(result.info["mono_sum_dev_db"]) < 1.0
    assert result.timer.total() > 0.0


def test_layers_can_be_disabled():
    sr = 44100
    legacy = synth.degrade_to_legacy(synth.make_modern_reference(sr=sr, dur=3.0), sr=sr)
    cfg = RemasterConfig(do_dehiss=False, do_bwe=False, do_match_eq=False, do_width=False)
    result = remaster(legacy, sr, cfg)
    assert "dehiss" not in result.timer.times
    assert "bandwidth_ext" not in result.timer.times
    assert np.all(np.isfinite(result.audio))
