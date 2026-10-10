"""Item 4: predictor resolution trade-off (bins per octave, block hop) -- error vs measured, 7 tracks x 15 curves."""
import numpy as np
from scipy import signal
import loudness_v2 as L, geq2 as G
tracks = {k: L.load(p) for k, p in L.FILES.items()}
fs_, x_ = tracks["band excerpt"]; tracks["LOUD master"] = (fs_, L.loud_master(x_, fs_))
def bands(x, fs, per_oct, hop):
    kw = signal.sosfilt(L.kweight_sos(fs), x, axis=0); Lw, H = int(0.4 * fs), int(hop * fs); n = 1 + (len(kw) - Lw) // H
    nfft = 1 << int(np.ceil(np.log2(Lw))); f = np.fft.rfftfreq(nfft, 1 / fs)
    edges = 20 * 2 ** (np.arange(0, 11 * per_oct) / per_oct); edges = np.r_[0, edges[edges < fs / 2], fs / 2 + 1]
    cen = np.sqrt(np.maximum(edges[:-1], 10) * edges[1:]); which = np.digitize(f, edges) - 1; P = np.zeros((n, len(cen)))
    for i in range(n):
        S = (np.abs(np.fft.rfft(kw[i * H:i * H + Lw], nfft, axis=0)) ** 2).sum(1); S[1:-1] *= 2
        P[i] = np.bincount(which, S, minlength=len(cen))[:len(cen)] / (Lw * nfft)
    return cen, P
res = {}
for tn, (fs, x) in tracks.items():
    Lsrc = L.gated(L.block_ms(x, fs))
    meas = {}
    for cn, t in L.curves().items():
        g = G.design(t, fs, 5); y = signal.sosfilt(L.eq_sos(g, fs), x, axis=0); meas[cn] = (g, L.gated(L.block_ms(y, fs)) - Lsrc)
    for po, hop in [(6, 0.1), (12, 0.1), (24, 0.1), (12, 0.4), (6, 0.4)]:
        cen, P = bands(x, fs, po, hop)
        for cn, (g, dm) in meas.items():
            H2 = 10 ** (G.response_db(g, cen, fs, G.C, "bilinear") / 10)
            res.setdefault((po, hop), []).append(L.gated(P @ H2) - L.gated(P.sum(1)) - dm)
    print("done", tn, flush=True)
lines = [__doc__]
for k, e in res.items():
    e = np.abs(e); lines.append(f"  1/{k[0]:2d} oct bins, hop {int(k[1]*1000):3d} ms: max {e.max():.3f} dB, p90 {np.percentile(e,90):.3f}, mean {e.mean():.3f}  (floats per minute of audio: {int(60/k[1]) * (11*k[0])})")
open("results/s4b_predictor_resolution.txt", "w").write("\n".join(lines) + "\n"); print("\n".join(lines))
