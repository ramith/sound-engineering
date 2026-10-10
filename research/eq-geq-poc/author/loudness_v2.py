"""Item 4: the loudness-neutral output gain (decision 26), measured on the repo's 7-track corpus.
Predictor (SOTA reviewer's design, re-implemented here): per BS.1770 block (400 ms, 100 ms hop) keep the K-weighted
source power in 1/24-octave bins (channel sum); for a curve H the EQ'd loudness is the BS.1770 two-stage-gated
loudness of sum_b P_blk(b)|H(f_b)|^2.  Output gain = -(predicted change).  Compared with the measured BS.1770 change
of the actually filtered track.  Also: the running (causal) estimate in the first seconds, the On<->Off integrated
difference with the gain the RT would really apply, and the true-peak load on the -1 dBTP limiter at -16 LUFS."""
import numpy as np, json
from scipy.io import wavfile
from scipy import signal
import geq2 as G
from geq import predicted_loudness_change_db
ROOT = "/Users/ramith/code/sound-engineering/research/"
FILES = {"old recording": "reimagine-poc/data/seetha_excerpt.wav", "band excerpt": "reimagine-poc/out/band_excerpt.wav",
         "gen band": "reimagine-poc/out/backing/turbo_band.wav", "gen cinematic": "reimagine-poc/out/backing/turbo_cinematic.wav",
         "gen folkpop": "reimagine-poc/out/backing/turbo_folkpop.wav", "remaster 3.7 min": "legacy-remaster-poc/out/tuned.wav"}
def load(p):
    fs, x = wavfile.read(ROOT + p)
    x = x / (32768.0 if x.dtype == np.int16 else 2147483648.0)
    return float(fs), x.astype(float)
def kweight_sos(fs):            # BS.1770 K-weighting re-derived for any fs (standard pre-filter + RLB parameters)
    G0, Q1, f1 = 3.999843853973347, 0.7071752369554196, 1681.974450955533
    A = 10 ** (G0 / 40); w = 2 * np.pi * f1 / fs; al = np.sin(w) / (2 * Q1); c = np.cos(w); sA = 2 * np.sqrt(A) * al
    b = [A * ((A + 1) + (A - 1) * c + sA), -2 * A * ((A - 1) + (A + 1) * c), A * ((A + 1) + (A - 1) * c - sA)]
    a = [(A + 1) - (A - 1) * c + sA, 2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - sA]
    Q2, f2 = 0.5003270373238773, 38.13547087602444; w = 2 * np.pi * f2 / fs; al = np.sin(w) / (2 * Q2); c = np.cos(w)
    b2 = [(1 + c) / 2, -(1 + c), (1 + c) / 2]; a2 = [1 + al, -2 * c, 1 - al]
    return np.vstack([np.r_[b, a] / a[0], np.r_[b2, a2] / a2[0]])
def gated(z):                   # BS.1770 integrated loudness from block mean-square powers (channel-summed)
    lk = -0.691 + 10 * np.log10(z + 1e-30); z1 = z[lk > -70]
    if z1.size == 0: return -200.0
    rel = -0.691 + 10 * np.log10(z1.mean()) - 10; z2 = z1[(-0.691 + 10 * np.log10(z1)) > rel]
    return -0.691 + 10 * np.log10(z2.mean())
def block_ms(x, fs):
    kw = signal.sosfilt(kweight_sos(fs), x, axis=0); L, H = int(0.4 * fs), int(0.1 * fs); n = 1 + (len(kw) - L) // H
    cs = np.vstack([np.zeros((1, kw.shape[1])), np.cumsum(kw ** 2, axis=0)])
    return ((cs[np.arange(n) * H + L] - cs[np.arange(n) * H]) / L).sum(1)
def block_bands(x, fs, per_oct=24):
    kw = signal.sosfilt(kweight_sos(fs), x, axis=0); L, H = int(0.4 * fs), int(0.1 * fs); n = 1 + (len(kw) - L) // H
    nfft = 1 << int(np.ceil(np.log2(L))); f = np.fft.rfftfreq(nfft, 1 / fs)
    edges = 20 * 2 ** (np.arange(0, 11 * per_oct) / per_oct); edges = np.r_[0, edges[edges < fs / 2], fs / 2 + 1]
    cen = np.sqrt(np.maximum(edges[:-1], 10) * edges[1:]); which = np.digitize(f, edges) - 1
    P = np.zeros((n, len(cen)))
    for i in range(n):
        S = (np.abs(np.fft.rfft(kw[i * H:i * H + L], nfft, axis=0)) ** 2).sum(1); S[1:-1] *= 2
        P[i] = np.bincount(which, S, minlength=len(cen))[:len(cen)] / (L * nfft)
    return cen, P
def loud_master(x, fs, target=-9.0):
    y = x * 10 ** ((target - gated(block_ms(x, fs))) / 20); pk = np.abs(y).max(1); need = np.minimum(1, 0.966 / np.maximum(pk, 1e-12))
    la = int(0.005 * fs); g = np.minimum.reduce([np.r_[need[k:], np.ones(k)] for k in range(la)])
    r = np.exp(-1 / (0.05 * fs)); s = 1.0; out = np.empty_like(g)
    for i, v in enumerate(g): s = v if v < s else r * s + (1 - r) * v; out[i] = s
    return y * np.minimum(out, g)[:, None]
def eq_sos(g, fs):
    b, a = G.cascade(g, fs, G.C, "bilinear"); return np.hstack([b, a])
def curves():
    c = dict(G.PRESETS)
    for i, lab in ((7, "+12 @100 Hz"), (17, "+12 @1 kHz"), (26, "+12 @8 kHz")): t = np.zeros(G.NB); t[i] = 12; c[lab] = t
    t = np.zeros(G.NB); t[17] = -12; c["-12 @1 kHz"] = t
    c["Tone Bass+6"] = G.apply_tone(np.zeros(G.NB), [6, 0, 0, 0, 0]); c["Tone Air+6"] = G.apply_tone(np.zeros(G.NB), [0, 0, 0, 0, 6])
    c["Tone B+6 Bo-3 P+4 A+6"] = G.apply_tone(np.zeros(G.NB), [6, -3, 0, 4, 6]); c["all -12"] = np.full(G.NB, -12.0)
    c["alternating"] = np.where(np.arange(G.NB) % 2 == 0, 12.0, -12.0)
    return c
def tp_frames(y, fs, frame=0.01):
    up = signal.resample_poly(y, 4, 1, axis=0); a = np.abs(up).max(1); F = int(frame * fs * 4); n = len(a) // F
    return 20 * np.log10(a[:n * F].reshape(n, F).max(1) + 1e-12)
if __name__ == "__main__":
    tracks = {k: load(p) for k, p in FILES.items()}
    fs_, x_ = tracks["band excerpt"]; tracks["LOUD master (synthetic, -9 LUFS)"] = (fs_, loud_master(x_, fs_))
    LG = np.geomspace(20, 20000, 2000); rows = []; summary = {"full": [], "pink": [], "run": {}, "onoff": [], "lim": []}
    for tn, (fs, x) in tracks.items():
        cen, P = block_bands(x, fs); Lsrc = gated(block_ms(x, fs)); n = P.shape[0]
        Psrc = gated(P.sum(1))
        tp_src = tp_frames(x * 10 ** (np.clip(-16 - Lsrc, -20, 12) / 20), fs)
        for cn, t in curves().items():
            g = G.design(t, fs, 5); H2 = 10 ** (G.response_db(g, cen, fs, G.C, "bilinear") / 10)
            y = signal.sosfilt(eq_sos(g, fs), x, axis=0); zy = block_ms(y, fs); dmeas = gated(zy) - Lsrc
            dfull = gated(P @ H2) - Psrc
            dpink = predicted_loudness_change_db(G.response_db(g, LG, fs, G.C, "bilinear"))
            # running (causal) estimate after t seconds of the track
            run = {}
            for ts in (1, 2, 3, 5, 10, 20, 30):
                k = int(ts * 10) - 3
                run[ts] = (gated(P[:k] @ H2) - gated(P[:k].sum(1))) if k >= 1 else np.nan
            # the gain the RT would apply: running estimate re-evaluated every 1 s from 3 s on (pink prior before),
            # slew-limited to 1 dB/s, applied per 100 ms hop; then the integrated On-vs-Off difference of the output
            gain_db = np.empty(len(zy)); cur = -dpink
            for i in range(len(zy)):
                if i >= 30 and i % 10 == 0:
                    est = -(gated(P[:i] @ H2) - gated(P[:i].sum(1)))
                    cur += np.clip(est - cur, -1.0, 1.0)
                gain_db[i] = cur
            onoff_int = gated(zy * 10 ** (gain_db / 10)) - Lsrc
            onoff_first10 = gated(zy[:97] * 10 ** (gain_db[:97] / 10)) - gated(block_ms(x, fs)[:97])
            onoff_static = gated(zy * 10 ** (-dfull / 10)) - Lsrc
            # limiter load at -16 LUFS (the normaliser's steady state; EQ is loudness-neutral so its makeup is unchanged)
            tp = tp_frames(y * 10 ** ((-dfull + np.clip(-16 - Lsrc, -20, 12)) / 20), fs)
            over = tp - (-1.0)
            rows.append(dict(track=tn, curve=cn, meas=dmeas, full=dfull, pink=dpink, run=run, onoff_int=onoff_int,
                             onoff_static=onoff_static, onoff_first10=onoff_first10,
                             lim_max=float(over.max()), lim_pct=float(100 * np.mean(over > 0)),
                             src_lim_max=float((tp_src + 1).max()), src_lim_pct=float(100 * np.mean(tp_src > -1))))
        print("done", tn, flush=True)
    json.dump(rows, open("results/s4_loudness_rows.json", "w"), indent=1, default=float)
    e_full = np.array([r["full"] - r["meas"] for r in rows]); e_pink = np.array([r["pink"] - r["meas"] for r in rows])
    lines = [__doc__, f"pairs: {len(rows)} (7 tracks x {len(curves())} curves)",
             f"predictor error vs measured BS.1770 change: gated block-spectral (full track) max {np.abs(e_full).max():.3f} dB, p90 {np.percentile(np.abs(e_full),90):.3f}, mean {np.abs(e_full).mean():.3f}",
             f"                                            curve on pink (v1)          max {np.abs(e_pink).max():.3f} dB, p90 {np.percentile(np.abs(e_pink),90):.3f}"]
    lines.append("running (causal) estimate error vs the final measured change, |err| max / p90, after t s:")
    for ts in (1, 2, 3, 5, 10, 20, 30):
        e = np.array([r["run"][ts] - r["meas"] for r in rows]); e = e[np.isfinite(e)]
        lines.append(f"   t = {ts:2d} s: max {np.abs(e).max():.2f}  p90 {np.percentile(np.abs(e),90):.2f}")
    oi = np.array([r["onoff_int"] for r in rows]); os_ = np.array([r["onoff_static"] for r in rows]); o10 = np.array([r["onoff_first10"] for r in rows])
    lines.append(f"On vs Off, integrated over the track, with the gain the RT applies (pink prior 0-3 s, running estimate every 1 s, slew 1 dB/s): max |diff| {np.abs(oi).max():.3f} dB, p90 {np.percentile(np.abs(oi),90):.3f}")
    lines.append(f"On vs Off, integrated, static full-track gain (load-time pre-analysis): max |diff| {np.abs(os_).max():.3f} dB, p90 {np.percentile(np.abs(os_),90):.3f}")
    lines.append(f"On vs Off over the first 10 s only (causal schedule): max |diff| {np.abs(o10).max():.2f} dB, p90 {np.percentile(np.abs(o10),90):.2f}")
    lm = np.array([r["lim_max"] for r in rows]); lp = np.array([r["lim_pct"] for r in rows])
    lines.append(f"limiter load at -16 LUFS (4x true peak over -1 dBTP): worst excess {lm.max():+.2f} dB, worst share of 10 ms frames {lp.max():.2f} %; "
                 f"source alone: worst excess {max(r['src_lim_max'] for r in rows):+.2f} dB, {max(r['src_lim_pct'] for r in rows):.2f} %")
    lines.append("\nper track x curve: measured | full | pink | onoff_int | lim excess dB (% frames)")
    for r in rows:
        lines.append(f"  {r['track'][:22]:22s} {r['curve']:22s} {r['meas']:+6.2f} | {r['full']:+6.2f} | {r['pink']:+6.2f} | {r['onoff_int']:+6.3f} | {r['lim_max']:+5.2f} ({r['lim_pct']:.2f})")
    txt = "\n".join(lines); open("results/s4_loudness.txt", "w").write(txt + "\n"); print("\n".join(lines[:20]))
