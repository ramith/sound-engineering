"""Process-ahead buffer simulation (spike report §3).

Models the streaming "Quick Remaster" regime: a head-start H pre-fills a ring buffer,
then the chain runs at real-time factor R (processing-sec per audio-sec). With R < 1 the
buffer grows without bound; at R >= 1 it eventually starves. This quantifies the margin.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np


@dataclass
class ProcessAheadResult:
    t: np.ndarray            # playback time axis (s)
    buffer_s: np.ndarray     # seconds of processed audio buffered ahead of the playhead
    min_buffer_s: float
    starved: bool            # did the buffer ever hit zero during playback?
    headstart_s: float
    rtf: float


def simulate_process_ahead(
    rtf: float,
    headstart_s: float = 5.0,
    duration_s: float = 240.0,
    dt: float = 0.05,
) -> ProcessAheadResult:
    """Simulate buffer depth over a track.

    During the head-start, no playback occurs and the buffer fills at rate 1/rtf.
    During playback, audio is consumed at 1x while processing continues at 1/rtf, so the
    net fill rate is (1/rtf - 1). Returns the buffer-depth trajectory and whether it starved.
    """
    if rtf <= 0:
        raise ValueError("rtf must be positive")
    b0 = headstart_s / rtf                       # buffered audio at playback start
    net_rate = (1.0 / rtf) - 1.0                 # seconds of audio gained per second of playback
    t = np.arange(0.0, duration_s, dt)
    buffer_s = b0 + net_rate * t
    buffer_s = np.maximum(buffer_s, 0.0)         # a real buffer can't go negative
    min_buffer = float(buffer_s.min())
    return ProcessAheadResult(
        t=t,
        buffer_s=buffer_s,
        min_buffer_s=min_buffer,
        starved=min_buffer <= 0.0,
        headstart_s=headstart_s,
        rtf=rtf,
    )


def max_streamable_duration(rtf: float, headstart_s: float) -> float:
    """If rtf >= 1, the longest track that streams without starving; else infinite."""
    if rtf <= 1.0:
        # rtf < 1: buffer grows without bound. rtf == 1: constant margin (= the head-start of
        # buffered audio) with zero growth -> any transient spike above 1.0 erodes it. The
        # streaming target is rtf <= 0.7 (spike report), NOT merely <= 1.0.
        return float("inf")
    # rtf > 1: buffer hits zero when headstart/rtf + (1/rtf - 1) * t = 0
    return (headstart_s / rtf) / (1.0 - 1.0 / rtf)
