"""Legacy-recording "Quick Remaster" POC — faithful, streaming-oriented chain.

Implemented layer order (see docs/session-notes/legacy-remaster-research-spike.md §2 and
pipeline.py): de-hiss -> bandwidth extension -> match-EQ -> width -> LUFS normalize -> true-peak
limit. (De-click and a dedicated virtual-bass stage from the report are not implemented here.)

This package implements the *faithful* (no-hallucination) layers in pure NumPy/SciPy
so the whole chain runs offline and faster-than-real-time, and every layer is verifiable.
"""

__all__ = [
    "audioio",
    "dsp",
    "dehiss",
    "bwe_classical",
    "match_eq",
    "loudness",
    "width",
    "verify",
    "pipeline",
    "synth",
    "sim",
    "bakeoff",
    "cli",
]
