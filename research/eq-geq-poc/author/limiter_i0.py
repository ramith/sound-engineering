"""Item 5: limiter load at Intensity 0 with the EQ On (new Branch 1b: EQ -> limiter, no normaliser, so the level stays
the source's). 4x true peak over -1 dBTP: worst excess and share of 10 ms frames, EQ On (loudness-neutral) vs the
source itself (which Intensity 0 + EQ Off plays bit-perfect, unlimited)."""
import numpy as np
from scipy import signal
import loudness_v2 as L, geq2 as G
tracks = {k: L.load(p) for k, p in L.FILES.items()}
fs_, x_ = tracks["band excerpt"]; tracks["LOUD master (-9 LUFS)"] = (fs_, L.loud_master(x_, fs_))
lines = [__doc__]
for tn, (fs, x) in tracks.items():
    Lsrc = L.gated(L.block_ms(x, fs)); src = L.tp_frames(x, fs) + 1; worst = (-99, 0, "")
    for cn in ["Warm", "Presence", "Tone B+6 Bo-3 P+4 A+6", "+12 @100 Hz", "-12 @1 kHz", "Loudness"]:
        g = G.design(L.curves()[cn], fs, 5); y = signal.sosfilt(L.eq_sos(g, fs), x, axis=0)
        y *= 10 ** ((Lsrc - L.gated(L.block_ms(y, fs))) / 20); o = L.tp_frames(y, fs) + 1
        if o.max() > worst[0]: worst = (o.max(), 100 * np.mean(o > 0), cn)
    lines.append(f"  {tn[:24]:24s} source TP excess {src.max():+5.2f} dB ({100*np.mean(src>0):.2f} % frames) | EQ On worst {worst[0]:+5.2f} dB ({worst[1]:.2f} %) [{worst[2]}]")
open("results/s5b_limiter_intensity0.txt", "w").write("\n".join(lines) + "\n"); print("\n".join(lines))
