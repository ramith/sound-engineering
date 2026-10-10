"""Item 4: what a press-and-hold Compare hears. With the static loudness-neutral gain (integrated match), the
short-term (3 s) loudness of On vs Off still wanders as the music's spectrum changes. p05..p95 and max of
L_short(On) - L_short(Off) over 3 s windows (1 s hop), 7 tracks."""
import numpy as np
from scipy import signal
import loudness_v2 as L, geq2 as G
tracks = {k: L.load(p) for k, p in L.FILES.items()}
fs_, x_ = tracks["band excerpt"]; tracks["LOUD master"] = (fs_, L.loud_master(x_, fs_))
def st(z):   # 3 s short-term from 100 ms hop / 400 ms blocks: average 30 hop-aligned mean squares over 3 s windows
    k = 30 - 3; return np.array([-0.691 + 10 * np.log10(z[i:i + k].mean() + 1e-30) for i in range(0, len(z) - k, 10)])
lines = [__doc__]
for cn in ["Warm", "Presence", "Tone B+6 Bo-3 P+4 A+6", "+12 @100 Hz", "-12 @1 kHz"]:
    d = []
    for tn, (fs, x) in tracks.items():
        t = L.curves()[cn]; g = G.design(t, fs, 5); y = signal.sosfilt(L.eq_sos(g, fs), x, axis=0)
        zx, zy = L.block_ms(x, fs), L.block_ms(y, fs); gain = L.gated(zx) - L.gated(zy)   # oracle static gain
        sx, sy = st(zx), st(zy * 10 ** (gain / 10)); ok = sx > -50; d.append((sy - sx)[ok])
    d = np.concatenate(d)
    lines.append(f"  {cn:24s} p05 {np.percentile(d,5):+.2f}  p95 {np.percentile(d,95):+.2f}  max|.| {np.abs(d).max():.2f} dB")
open("results/s4c_shortterm.txt", "w").write("\n".join(lines) + "\n"); print("\n".join(lines))
