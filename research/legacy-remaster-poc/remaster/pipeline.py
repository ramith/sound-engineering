"""Quick-Remaster pipeline — chains the faithful layers in the report's order and times each.

    de-hiss -> bandwidth extension -> match-EQ -> width -> LUFS normalize -> true-peak limit

Loudness normalization and the limiter are LAST (and in that order) on purpose: width
changes level — and turning mono into stereo raises the BS.1770 reading by ~3 dB (dual-mono)
— so we normalize the *final* signal, then guarantee the true-peak ceiling as the last step.

(De-click is omitted from this POC; broadband hiss + rolloff are the dominant legacy issues.)

The match-EQ reference is optional: pass a modern track to match its tonal balance, or omit
it to skip tone-matching (bandwidth extension alone already brightens).
"""
from __future__ import annotations

import logging
from dataclasses import dataclass, field

import numpy as np

from . import bwe_classical, dehiss, dsp, loudness, match_eq, width
from .audioio import as_2d, is_stereo, to_mono
from .verify import Timer

log = logging.getLogger(__name__)


@dataclass
class RemasterConfig:
    # de-hiss
    do_dehiss: bool = True
    dehiss_alpha: float = 0.95
    dehiss_overestimate: float = 1.0
    noise_start: float | None = None      # explicit noise-only segment (s)
    noise_dur: float | None = None
    # bandwidth extension (classical baseline; swap in a learned model via the bake-off)
    do_bwe: bool = True
    bwe_rolloff_hz: float | None = None    # None = auto-detect
    bwe_drive: float = 2.5
    bwe_mix_db: float = -3.0
    # tone / loudness / width
    do_match_eq: bool = True
    target_lufs: float = -14.0
    tp_ceiling_db: float = -1.0
    do_width: bool = True
    width_amount: float = 0.4
    # analysis
    n_fft_dehiss: int = 2048


@dataclass
class RemasterResult:
    audio: np.ndarray
    sr: int
    timer: Timer
    info: dict = field(default_factory=dict)


def remaster(
    x: np.ndarray,
    sr: int,
    cfg: RemasterConfig | None = None,
    reference: np.ndarray | None = None,
) -> RemasterResult:
    """Run the Quick-Remaster chain. Returns processed audio + timings + an info dict."""
    cfg = cfg or RemasterConfig()
    x = np.asarray(x, dtype=np.float64)
    if sr <= 0:
        raise ValueError(f"sample rate must be positive, got {sr}")
    if x.size == 0:
        raise ValueError("input audio is empty")
    if not np.all(np.isfinite(x)):
        raise ValueError("input audio contains NaN or Inf")
    t = Timer()
    info: dict = {}
    y = x
    audio_s = len(to_mono(x)) / sr
    log.info("remaster: %.1fs @ %d Hz, %d ch", audio_s, sr, as_2d(x).shape[1])

    if cfg.do_dehiss:
        seg = "explicit noise segment" if cfg.noise_start is not None else "blind percentile estimate"
        log.info("[1/6] de-hiss (log-MMSE, alpha=%.2f, %s) ...", cfg.dehiss_alpha, seg)
        with t.stage("dehiss"):
            y = dehiss.dehiss(
                y, sr,
                n_fft=cfg.n_fft_dehiss,
                alpha=cfg.dehiss_alpha,
                noise_overestimate=cfg.dehiss_overestimate,
                noise_start=cfg.noise_start,
                noise_dur=cfg.noise_dur,
            )
        log.info("[1/6] de-hiss done in %.2fs (RTF %.3f)", t.times["dehiss"], t.times["dehiss"] / audio_s)
    else:
        log.info("[1/6] de-hiss skipped")

    # Determine the HF rolloff ONCE (driven by cfg, else auto-detected on the post-de-hiss
    # signal). Shared by BWE (what to extend above) AND the match-EQ taper (what not to boost
    # above) — so the taper protects the HF residual whether or not BWE runs (review N1). This
    # is an explicit value, not threaded through the reporting `info` dict.
    rolloff = cfg.bwe_rolloff_hz if cfg.bwe_rolloff_hz is not None else dsp.estimate_rolloff(to_mono(y), sr)
    info["rolloff_hz"] = rolloff

    if cfg.do_bwe:
        log.info("[2/6] bandwidth extension (harmonic synthesis) ...")
        with t.stage("bandwidth_ext"):
            y, _ = bwe_classical.extend_bandwidth(
                y, sr, rolloff_hz=rolloff, drive=cfg.bwe_drive, mix_db=cfg.bwe_mix_db
            )
        log.info(
            "[2/6] BWE done in %.2fs (RTF %.3f), rolloff=%.0f Hz",
            t.times["bandwidth_ext"], t.times["bandwidth_ext"] / audio_s, rolloff,
        )
    else:
        log.info("[2/6] bandwidth extension skipped")

    if cfg.do_match_eq and reference is not None:
        log.info("[3/6] match-EQ to reference ...")
        with t.stage("match_eq"):
            # fade the correction out above the rolloff so it can't amplify the de-hiss HF
            # residual (review H-3); the high end is owned by BWE (or left alone if BWE is off).
            y, (f, gain_db) = match_eq.match_eq(y, reference, sr, rolloff_hz=rolloff)
            info["eq_curve"] = (f, gain_db)
        log.info(
            "[3/6] match-EQ done in %.2fs, curve span %.1f..%.1f dB",
            t.times["match_eq"], float(gain_db.min()), float(gain_db.max()),
        )
    else:
        log.info("[3/6] match-EQ skipped (%s)", "no reference" if reference is None else "disabled")

    if cfg.do_width:
        log.info("[4/6] stereo width (amount=%.2f) ...", cfg.width_amount)
        with t.stage("width"):
            mono_before = to_mono(y).copy()
            y = width.widen(y, sr, width=cfg.width_amount)
            if is_stereo(y):
                info["mono_sum_dev_db"] = width.mono_sum_deviation_db(y, mono_before)
        log.info("[4/6] width done (mono-sum dev %+.2f dB)", info.get("mono_sum_dev_db", 0.0))
    else:
        log.info("[4/6] width skipped")

    log.info("[5/6] LUFS normalize -> %.1f LUFS ...", cfg.target_lufs)
    with t.stage("lufs"):
        y, measured_lufs, gain_db = loudness.normalize_lufs(y, sr, cfg.target_lufs)
        info["input_lufs"] = measured_lufs
        info["lufs_gain_db"] = gain_db
    log.info("[5/6] input %.2f LUFS, applied %+.2f dB", measured_lufs, gain_db)

    log.info("[6/6] true-peak limit -> %.1f dBTP ...", cfg.tp_ceiling_db)
    with t.stage("true_peak_limit"):
        y, tp_in = loudness.true_peak_limit(y, sr, ceiling_db=cfg.tp_ceiling_db)
        info["true_peak_in_dbtp"] = tp_in
    log.info("[6/6] input true peak %.2f dBTP", tp_in)

    log.info("remaster complete: total %.2fs, RTF %.3f", t.total(), t.total() / audio_s)
    return RemasterResult(audio=y, sr=sr, timer=t, info=info)
