"""Item 2 (time-domain half): S1 (shared dB ramp) vs S2 (finished (k, m1) smoother), both with the loudness-neutral
output gain riding the same smoother, tau = 10 ms, 48 kHz, double TPT SVF. Sine probes through cpp/tdsim.
  TD overshoot local: max envelope after the switch / max(steady A, steady B) at the same probe frequency.
  TD overshoot peak : max over probes of the post-switch envelope / max over probes of max(steady A, steady B).
  SB  : Wishnick-style sideband energy (85 ms Hann, 5 ms hop, +-1 ERB around the probe removed), max over the
        transition, dB re the window energy; SBref = the same on an ideal analytic dB/phase crossfade (tau 10 ms).
  Etr : energy of (output - ideal crossfade) / energy of the ideal, over the transition window, dB."""
import numpy as np, os, subprocess, itertools
from concurrent.futures import ThreadPoolExecutor
from scipy.signal import hilbert
import geq2 as G
from geq import predicted_loudness_change_db
fs = 48000.0; TAU = 0.010; AMP = 0.25; T0 = 0.30; N = int(0.80 * fs)
LG = np.geomspace(20, 20000, 2000)
BIN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cpp/tdsim")
_c = {}
def ep(t):
    key = tuple(np.round(t, 6))
    if key not in _c:
        g = G.design(t, fs, 5); out = -predicted_loudness_change_db(G.response_db(g, LG, fs, G.C, "bilinear"))
        k, m = G.km_of(g, fs); _c[key] = (g, k, m, out)
    return _c[key]
_id = iter(range(10**9))
def run(events, mode, probe, n=N):
    i = next(_id); cf = f"tmp/c{i}.txt"; of = f"tmp/o{i}.f32"
    with open(cf, "w") as fh:
        fh.write(f"{fs} {n} {TAU} {mode} {probe} {AMP} {len(events)}\n")
        for t, e in events:
            fh.write(f"{t} " + " ".join(f"{v:.17g}" for v in np.concatenate([e[0], e[1], e[2], [e[3]]])) + "\n")
    subprocess.run([BIN, cf, of], check=True)
    y = np.fromfile(of, np.float32).astype(float); os.remove(cf); os.remove(of); return y
def overshoot(tA, tB, mode, probes):
    A, B = ep(tA), ep(tB); n0 = int(T0 * fs)
    def one(p):
        env = np.abs(hilbert(run([(0.0, A), (T0, B)], mode, p)))
        a = np.median(env[n0 - int(0.08 * fs):n0 - int(0.01 * fs)]); b = np.median(env[-int(0.1 * fs):-int(0.03 * fs)])
        return env[n0:n0 + int(0.25 * fs)].max(), a, b
    with ThreadPoolExecutor(10) as ex: r = np.array(list(ex.map(one, probes)))
    loc = 20 * np.log10(r[:, 0] / np.maximum(r[:, 1], r[:, 2]))
    peak = 20 * np.log10(r[:, 0].max() / np.maximum(r[:, 1], r[:, 2]).max())
    return loc.max(), probes[int(np.argmax(loc))], peak
PROBES = np.geomspace(25, 18000, 48)
if __name__ == "__main__":
    flat = np.zeros(G.NB); h = G.hard_set(); cur = dict(G.PRESETS); cur["Off"] = flat
    wp = np.load("../../review/breaker/worst_pair.npy"); a1 = np.load("results/adv_pair_S1.npy"); a2 = np.load("results/adv_pair_S2.npy")
    named = {"breaker worst pair A->B": (wp[0], wp[1]), "breaker worst pair B->A": (wp[1], wp[0]),
             "S1-adversarial pair": (a1[0], a1[1]), "S2-adversarial pair": (a2[0], a2[1]),
             "alt+ -> alt-": (h["alternating"], -h["alternating"]),
             "Warm -> Off": (cur["Warm"], flat), "Off -> Warm": (flat, cur["Warm"]),
             "alternating -> Off": (h["alternating"], flat), "Off -> alternating": (flat, h["alternating"]),
             "every-third-down -> Off": (h["every-third-down/0"], flat), "Off -> all+12": (flat, h["all+12"])}
    lines = [__doc__, "A) Time-domain overshoot (dB): local [worst probe Hz] / peak", f"{'transition':28s} {'S1 dB-ramp':>26s} {'S2 (k,m1)':>26s}"]
    for nm, (a, b) in named.items():
        r = [overshoot(a, b, m, PROBES) for m in (0, 1)]
        lines.append(f"{nm:28s} " + "  ".join(f"{x[0]:+6.2f} [{x[1]:6.0f}] / {x[2]:+6.2f}" for x in r)); print(lines[-1], flush=True)
    pp = [(cur[x], cur[y]) for x, y in itertools.permutations(cur, 2)]
    rs = np.array([[overshoot(a, b, m, PROBES[::2])[0::2] for m in (0, 1)] for a, b in pp])
    lines.append(f"{'42 preset pairs (incl. Off)':28s} S1 local {rs[:, 0, 0].max():+.3f} peak {rs[:, 0, 1].max():+.3f} | S2 local {rs[:, 1, 0].max():+.3f} peak {rs[:, 1, 1].max():+.3f}")
    print(lines[-1], flush=True)
    # B) sidebands + tracking against an ideal analytic crossfade
    def ideal(A, B, p):
        f = np.array([p]); HA = G.svf_cascade_cplx(A[1], A[2], fs, f)[0] * 10 ** (A[3] / 20); HB = G.svf_cascade_cplx(B[1], B[2], fs, f)[0] * 10 ** (B[3] / 20)
        n = np.arange(N); s = np.where(n >= int(T0 * fs), 1 - np.exp(-(n - int(T0 * fs)) / (TAU * fs)), 0.0)
        dphi = np.angle(HB / HA); mag = (1 - s) * 20 * np.log10(abs(HA)) + s * 20 * np.log10(abs(HB)); ph = np.angle(HA) + s * dphi
        return AMP * 10 ** (mag / 20) * np.sin(2 * np.pi * p / fs * n + ph)
    def sideband(y, p):
        L = int(0.085 * fs); hop = int(0.005 * fs); w = np.hanning(L); erb = 24.7 * (4.37 * p / 1000 + 1)
        fr = np.fft.rfftfreq(L, 1 / fs); keep = np.abs(fr - p) > erb; worst = -300
        for st in range(int(T0 * fs) - L // 2, int(T0 * fs) + int(0.1 * fs), hop):
            S = np.abs(np.fft.rfft(y[st:st + L] * w)) ** 2; worst = max(worst, 10 * np.log10(S[keep].sum() / S.sum() + 1e-30))
        return worst
    def sb_etr(tA, tB, p, events=None):
        A, B = ep(tA), ep(tB); yi = ideal(A, B, p); out = [sideband(yi, p)]
        win = slice(int(T0 * fs) - int(0.01 * fs), int(T0 * fs) + int(0.15 * fs))
        for m in (0, 1):
            y = run(events or [(0.0, A), (T0, B)], m, p)
            out += [sideband(y, p), 10 * np.log10(np.sum((y[win] - yi[win]) ** 2) / np.sum(yi[win] ** 2))]
        return out
    lines.append("\nB) Sidebands and tracking: SBref | S1 SB, Etr | S2 SB, Etr  (dB)")
    for nm, (a, b) in [("Off -> Warm", (flat, cur["Warm"])), ("Warm -> Presence", (cur["Warm"], cur["Presence"])),
                       ("Presence -> Off", (cur["Presence"], flat)), ("alternating -> Off", (h["alternating"], flat)),
                       ("breaker worst pair", (wp[0], wp[1]))]:
        for p in (100.0, 1000.0, 4000.0):
            r = sb_etr(a, b, p)
            lines.append(f"  {nm:20s} {p:6.0f} Hz  SBref {r[0]:7.1f} | S1 {r[1]:7.1f}, {r[2]:7.1f} | S2 {r[3]:7.1f}, {r[4]:7.1f}"); print(lines[-1], flush=True)
    txt = "\n".join(lines); open("results/s2c_transition_td.txt", "w").write(txt + "\n"); print("written")
