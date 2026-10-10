"""Item 4 cost check: a block's 1/24-oct band powers formed as the SUM of its four 100 ms hop spectra (one 8k FFT per
hop, reused by 4 blocks) instead of one 32k FFT per 400 ms block. Predictor error vs measured, 7 tracks x 15 curves."""
import numpy as np, time
from scipy import signal
import loudness_v2 as L, geq2 as G
tracks = {k: L.load(p) for k, p in L.FILES.items()}
fs_, x_ = tracks["band excerpt"]; tracks["LOUD master"] = (fs_, L.loud_master(x_, fs_))
def hop_bands(x, fs, per_oct=24):
    kw = signal.sosfilt(L.kweight_sos(fs), x, axis=0); H = int(0.1 * fs); nh = len(kw) // H
    nfft = 1 << int(np.ceil(np.log2(H))); f = np.fft.rfftfreq(nfft, 1 / fs)
    edges = 20 * 2 ** (np.arange(0, 11 * per_oct) / per_oct); edges = np.r_[0, edges[edges < fs / 2], fs / 2 + 1]
    cen = np.sqrt(np.maximum(edges[:-1], 10) * edges[1:]); which = np.digitize(f, edges) - 1
    S = (np.abs(np.fft.rfft(kw[:nh * H].reshape(nh, H, -1), nfft, axis=1)) ** 2).sum(2); S[:, 1:-1] *= 2
    Ph = np.stack([np.bincount(which, s, minlength=len(cen))[:len(cen)] for s in S]) / (H * nfft)
    return cen, (Ph[:-3] + Ph[1:-2] + Ph[2:-1] + Ph[3:]) / 4     # 400 ms block = mean of its 4 hops
errs = []; t_hop = 0
for tn, (fs, x) in tracks.items():
    Lsrc = L.gated(L.block_ms(x, fs)); t0 = time.time(); cen, P = hop_bands(x, fs); t_hop += time.time() - t0
    for cn, t in L.curves().items():
        g = G.design(t, fs, 5); y = signal.sosfilt(L.eq_sos(g, fs), x, axis=0); dm = L.gated(L.block_ms(y, fs)) - Lsrc
        H2 = 10 ** (G.response_db(g, cen, fs, G.C, "bilinear") / 10); errs.append(L.gated(P @ H2) - L.gated(P.sum(1)) - dm)
e = np.abs(errs)
txt = __doc__ + f"\n  hop-sum blocks, 1/24 oct: max {e.max():.3f} dB, p90 {np.percentile(e,90):.3f}, mean {e.mean():.3f}; numpy analysis time for {sum(len(v[1])/v[0] for v in tracks.values()):.0f} s of audio: {t_hop:.2f} s\n"
open("results/s4d_hopsum.txt", "w").write(txt); print(txt)
