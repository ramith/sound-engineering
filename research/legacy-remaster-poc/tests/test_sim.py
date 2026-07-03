import math

from remaster import sim


def test_process_ahead_stable_when_faster_than_realtime():
    res = sim.simulate_process_ahead(rtf=0.3, headstart_s=5.0, duration_s=240.0)
    assert not res.starved
    assert res.buffer_s[0] > 5.0           # 5 / 0.3 ~ 16.7 s buffered at start
    assert res.buffer_s[-1] > res.buffer_s[0]  # grows over time


def test_process_ahead_starves_when_slower_than_realtime():
    res = sim.simulate_process_ahead(rtf=2.0, headstart_s=5.0, duration_s=240.0)
    assert res.starved


def test_max_streamable_duration_math():
    # rtf=2, H=5  ->  (5/2)/(1 - 1/2) = 2.5 / 0.5 = 5 s
    assert math.isclose(sim.max_streamable_duration(2.0, 5.0), 5.0, rel_tol=1e-9)
    assert sim.max_streamable_duration(0.5, 5.0) == float("inf")


def test_rtf_must_be_positive():
    import pytest

    with pytest.raises(ValueError):
        sim.simulate_process_ahead(rtf=0.0)
