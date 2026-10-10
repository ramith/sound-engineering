"""Item 2, frozen model, both swell metrics, plus S3 = target-domain keyframes.
M_local = max_f [net_s(f) - max(net_A(f), net_B(f))]    a boost at some frequency that neither endpoint has
M_peak  = max_f net_s(f) - max(max_f net_A, max_f net_B)  a peak above both endpoints' peaks (limiter/safety view)
S1: dB ramp of solved gains + output gain.  S2: (k, m1) + output gain (dB).
S3(K): the Realizer solves K intermediate TARGETS t(i/K) = (1-i/K) tA + (i/K) tB; the RT moves through them with S2."""
import numpy as np, itertools, geq2 as G
from geq import predicted_loudness_change_db
rng = np.random.default_rng(11)
fs = 48000.0
F = np.geomspace(15, 0.4999 * fs, 1200)
LG = np.geomspace(20, 20000, 2000)
_c = {}
def ep(t):
    key = tuple(np.round(t, 6))
    if key not in _c:
        g = G.design(t, fs, 5); out = -predicted_loudness_change_db(G.response_db(g, LG, fs, G.C, "bilinear"))
        k, m = G.km_of(g, fs); _c[key] = (g, out, k, m, G.response_db(g, F, fs, G.C, "bilinear") + out)
    return _c[key]
def path_s1(A, B, s): return G.response_db((1 - s) * A[0] + s * B[0], F, fs, G.C, "bilinear") + (1 - s) * A[1] + s * B[1]
def path_s2(A, B, s): return G.svf_cascade_db((1 - s) * A[2] + s * B[2], (1 - s) * A[3] + s * B[3], fs, F) + (1 - s) * A[1] + s * B[1]
def metrics(tA, tB, scheme, K=8, ns=21):
    A, B = ep(tA), ep(tB); top = np.maximum(A[4], B[4]); pk = max(A[4].max(), B[4].max())
    if scheme in ("S1", "S2"):
        segs = [(A, B)]
    else:
        keys = [ep((1 - i / K) * tA + (i / K) * tB) for i in range(K + 1)]
        segs = list(zip(keys[:-1], keys[1:])); ns = max(3, ns // K + 2)
    ml = mp = -99
    for a, b in segs:
        for s in np.linspace(0, 1, ns):
            n = (path_s1 if scheme == "S1" else path_s2)(a, b, s)
            ml = max(ml, (n - top).max()); mp = max(mp, n.max() - pk)
    return ml, mp
flat = np.zeros(G.NB); h = G.hard_set(); cur = dict(G.PRESETS); cur["Flat/Off"] = flat
wp = np.load("../../review/breaker/worst_pair.npy"); a1 = np.load("results/adv_pair_S1.npy"); a2 = np.load("results/adv_pair_S2.npy")
named = {"breaker worst pair": (wp[0], wp[1]), "S1-adversarial pair": (a1[0], a1[1]), "S2-adversarial pair": (a2[0], a2[1]),
         "alt+ -> alt-": (h["alternating"], -h["alternating"]), "every-third-down -> Off": (h["every-third-down/0"], flat),
         "alternating -> Off": (h["alternating"], flat), "Off -> all+12": (flat, h["all+12"]), "Warm -> Presence": (cur["Warm"], cur["Presence"])}
schemes = ["S1", "S2", "S3"]
lines = [__doc__, f"{'pair':28s} " + "  ".join(f"{s+' local/peak':>16s}" for s in schemes)]
for n, (a, b) in named.items():
    r = [metrics(a, b, s) for s in schemes]
    lines.append(f"{n:28s} " + "  ".join(f"{x[0]:+7.2f}/{x[1]:+7.2f}" for x in r))
groups = {"42 preset pairs": [(cur[x], cur[y]) for x, y in itertools.permutations(cur, 2)],
          "hard patterns <-> Off": [p for t in h.values() for p in ((t, flat), (flat, t))],
          "100 smooth pairs": list(zip(G.smooth_set(rng, 100), G.smooth_set(rng, 100))),
          "100 Rämö pairs": list(zip(G.ramo_set(rng, 50, 50), G.ramo_set(rng, 50, 50)))}
lines.append("\nGroups, worst (local/peak):")
for n, pairs in groups.items():
    r = np.array([[metrics(a, b, s, ns=11) for s in schemes] for a, b in pairs])
    lines.append(f"  {n:24s} " + "  ".join(f"{sc} {r[:, i, 0].max():+6.2f}/{r[:, i, 1].max():+6.2f}" for i, sc in enumerate(schemes)))
for K in (2, 4, 16):
    r = [metrics(a, b, "S3", K=K) for a, b in [(wp[0], wp[1]), (a1[0], a1[1]), (a2[0], a2[1]), (h["alternating"], -h["alternating"])]]
    lines.append(f"S3 with K={K:2d} keyframes on the 3 adversarial pairs + alt flip: worst local {max(x[0] for x in r):+.2f}, peak {max(x[1] for x in r):+.2f}")
txt = "\n".join(lines); print(txt); open("results/s2b_transition_fd_metrics.txt", "w").write(txt + "\n")

# M_loud: pink K-weighted loudness of the net response during the transition vs the louder endpoint
def mloud(tA, tB, scheme, ns=21):
    A, B = ep(tA), ep(tB)
    def L(n): return predicted_loudness_change_db(np.interp(np.log(LG), np.log(F), n))
    top = max(L(A[4]), L(B[4]))
    return max(L((path_s1 if scheme == "S1" else path_s2)(A, B, s)) - top for s in np.linspace(0, 1, ns))
out = ["\nM_loud (pink K-weighted loudness bump above the louder endpoint), worst:"]
for n, pairs in list(groups.items()) + [("named adversarial", [(wp[0], wp[1]), (a1[0], a1[1]), (a2[0], a2[1])])]:
    r = np.array([[mloud(a, b, s, 11) for s in ("S1", "S2")] for a, b in pairs])
    out.append(f"  {n:24s} S1 {r[:, 0].max():+6.2f}   S2 {r[:, 1].max():+6.2f}")
print("\n".join(out)); open("results/s2b_transition_fd_metrics.txt", "a").write("\n".join(out) + "\n")
