"""Bandwidth-extension bake-off: compare BWE methods on the same input by HF-energy gain,
musical-noise (spectral kurtosis), and RTF — the data the spike report says we must measure
on real hardware (paper RTFs are NVIDIA/CPU).

The classical harmonic-synthesis baseline always runs. Learned runners (AERO, FlashSR) are
honest scaffolds: they detect whether torch + model weights are wired up and, if not, are
skipped with a clear message rather than faking a result. See bwe/README.md to enable them.
"""
from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from typing import Protocol, runtime_checkable

import numpy as np

from . import bwe_classical, verify
from .audioio import to_mono

log = logging.getLogger(__name__)


@runtime_checkable
class BWERunner(Protocol):
    name: str  # must be a class attribute on implementers (used as the result label)

    def available(self) -> tuple[bool, str]:
        """Return (is_available, reason_if_not_available)."""
        ...

    def run(self, x: np.ndarray, sr: int) -> np.ndarray:
        """Bandwidth-extend mono-or-stereo `x` at sample rate `sr`; return same shape."""
        ...


class ClassicalRunner:
    """Faithful harmonic-synthesis BWE — the always-available reference."""

    name = "classical"

    def __init__(self, drive: float = 2.5, mix_db: float = -3.0) -> None:
        self.drive = drive
        self.mix_db = mix_db

    def available(self) -> tuple[bool, str]:
        return True, ""

    def run(self, x: np.ndarray, sr: int) -> np.ndarray:
        return bwe_classical.extend_bandwidth(x, sr, drive=self.drive, mix_db=self.mix_db)[0]


class _TorchWeightsRunner:
    """Base for learned runners. Available only if torch imports AND a weights file exists at
    the env-configured path. `run` must be implemented per model (needs the model's repo)."""

    name = "torch-base"
    weights_env = "BWE_WEIGHTS"

    def available(self) -> tuple[bool, str]:
        try:
            import torch  # noqa: F401
        except ImportError:
            return False, "torch not installed (`pip install -e '.[ml]'`)"
        path = os.environ.get(self.weights_env)
        if not path or not os.path.exists(path):
            return False, f"set {self.weights_env}=<weights> and wire the model (see bwe/README.md)"
        return True, ""

    def run(self, x: np.ndarray, sr: int) -> np.ndarray:  # pragma: no cover - scaffold
        raise NotImplementedError(
            f"{self.name}: wire the upstream model in remaster/bakeoff.py per bwe/README.md."
        )


class AeroRunner(_TorchWeightsRunner):
    """AERO (Mandel/Tal/Adi 2023) — single-pass complex-spectrogram GAN. arXiv:2211.12232."""

    name = "aero"
    weights_env = "AERO_WEIGHTS"


class FlashSRRunner(_TorchWeightsRunner):
    """FlashSR (Im & Nam 2025) — one-step distilled diffusion SR. arXiv:2501.10807."""

    name = "flashsr"
    weights_env = "FLASHSR_WEIGHTS"


@dataclass
class BakeoffEntry:
    name: str
    rtf: float
    hf_energy_db: float          # energy in [10k, Nyquist] relative to full band
    hf_gain_db: float            # vs. the input
    kurtosis_delta: float        # spectral-kurtosis change vs input (musical-noise proxy)
    output: np.ndarray


def run_bakeoff(
    x: np.ndarray,
    sr: int,
    runners: list[BWERunner] | None = None,
    hf_floor: float = 10000.0,
) -> list[BakeoffEntry]:
    """Run each available runner on x, returning measured entries (input included as baseline).

    Metrics (HF gain, kurtosis delta) are measured relative to THIS `x`. Call with the original
    legacy signal so the deltas are meaningful; a partially-processed input makes that the
    baseline, not the original (review L-3)."""
    runners = runners or [ClassicalRunner(), AeroRunner(), FlashSRRunner()]
    audio_s = len(to_mono(x)) / sr

    in_hf = verify.hf_energy_db(x, sr, hf_floor)
    in_kurt = verify.spectral_kurtosis(x, sr)
    entries = [BakeoffEntry("input", 0.0, in_hf, 0.0, 0.0, x)]

    for r in runners:
        ok, reason = r.available()
        if not ok:
            log.info("skipping BWE runner %r: %s", r.name, reason)
            continue
        timer = verify.Timer()
        with timer.stage(r.name):
            y = r.run(x, sr)
        hf = verify.hf_energy_db(y, sr, hf_floor)
        entries.append(
            BakeoffEntry(
                name=r.name,
                rtf=timer.total() / audio_s,
                hf_energy_db=hf,
                hf_gain_db=hf - in_hf,
                kurtosis_delta=verify.spectral_kurtosis(y, sr) - in_kurt,
                output=y,
            )
        )
    return entries


def format_table(entries: list[BakeoffEntry]) -> str:
    rows = [f"  {'method':<12}{'RTF':>8}{'HF dB':>9}{'HF gain':>9}{'d-kurt':>9}"]
    for e in entries:
        rows.append(
            f"  {e.name:<12}{e.rtf:>8.4f}{e.hf_energy_db:>9.2f}"
            f"{e.hf_gain_db:>9.2f}{e.kurtosis_delta:>9.2f}"
        )
    return "\n".join(rows)
