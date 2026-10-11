"""Audiobox Aesthetics timing: one 30 s clip and one whole track, on CPU and on MPS.

usage: python -I aes_timing.py <checkpoint.pt> <clip.wav> <whole_track.wav>
"""

import sys
import time

import soundfile as sf
import torch

import audiobox_aesthetics.infer as infer


def run(device_name, ckpt, items, reps=3):
    orig = torch.backends.mps.is_available
    if device_name == "cpu":
        torch.backends.mps.is_available = lambda: False  # force the package's device pick to CPU
    try:
        pred = infer.AesPredictor(checkpoint_pth=ckpt)
    finally:
        torch.backends.mps.is_available = orig
    print(device_name, "device:", pred.device)
    for label, (x, fs) in items.items():
        seg = torch.from_numpy(x.T.copy()).float()
        pred.forward([{"path": seg, "sample_rate": fs}])  # warm-up
        if pred.device.type == "mps":
            torch.mps.synchronize()
        times = []
        for _ in range(reps):
            t0 = time.perf_counter()
            row = pred.forward([{"path": seg, "sample_rate": fs}])[0]
            if pred.device.type == "mps":
                torch.mps.synchronize()
            times.append(time.perf_counter() - t0)
        print(f"  {label}: {x.shape[0] / fs:.1f} s audio, best {min(times):.2f} s, "
              f"median {sorted(times)[len(times) // 2]:.2f} s  scores {row}")


def main():
    ckpt, clip, whole = sys.argv[1:4]
    torch.set_num_threads(10)
    xa, fsa = sf.read(clip, dtype="float32", always_2d=True)
    xw, fsw = sf.read(whole, dtype="float32", always_2d=True)
    items = {"30 s clip": (xa[: 30 * fsa], fsa), "whole track": (xw, fsw)}
    for dev in ("mps", "cpu"):
        run(dev, ckpt, items)


if __name__ == "__main__":
    main()
