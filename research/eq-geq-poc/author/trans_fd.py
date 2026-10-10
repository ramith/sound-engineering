"""Item 2 (frozen-model half): transition swell of the two schemes under decision 26 (loudness-neutral gain).
S1 = shared dB ramp: the 31 filter gains AND the output gain move on one one-pole (linear path in dB).
S2 = finished-coefficient SVF smoother: per-band (k, m1) and the output gain (dB) move on one one-pole.
Swell(s) = max_f [ net_s(f) - max(net_A(f), net_B(f)) ]: level that NEITHER endpoint has. Output gain = -dL on a
pink K-weighted reference (a stand-in for the track predictor; both endpoints carry their own gain)."""
import numpy as np, itertools, geq2 as G
from geq import predicted_loudness_change_db
rng = np.random.default_rng(11)
fs = 48000.0
F = np.geomspace(15, 0.4999 * fs, 1500)
LG = np.geomspace(20, 20000, 2000)
S = np.linspace(0, 1, 41)
cache = {}
def endpoint(t):
    key = tuple(np.round(t, 6))
    if key not in cache:
        g = G.design(t, fs, 5)
        out = -predicted_loudness_change_db(G.response_db(g, LG, fs, G.C, "bilinear"))
        k, m = G.km_of(g, fs)
        cache[key] = (g, out, k, m, G.response_db(g, F, fs, G.C, "bilinear") + out)
    return cache[key]
def swell(tA, tB, s_grid=S):
    gA, oA, kA, mA, nA = endpoint(tA); gB, oB, kB, mB, nB = endpoint(tB)
    top = np.maximum(nA, nB); w1 = w2 = -99.0; s1 = s2 = 0
    for s in s_grid:
        v1 = (G.response_db((1 - s) * gA + s * gB, F, fs, G.C, "bilinear") + (1 - s) * oA + s * oB - top).max()
        v2 = (G.svf_cascade_db((1 - s) * kA + s * kB, (1 - s) * mA + s * mB, fs, F) + (1 - s) * oA + s * oB - top).max()
        if v1 > w1: w1, s1 = v1, s
        if v2 > w2: w2, s2 = v2, s
    return w1, w2
flat = np.zeros(G.NB)
cur = dict(G.PRESETS); cur["Flat/Off"] = flat
h = G.hard_set()
wp = np.load("../../review/breaker/worst_pair.npy")
lines = [__doc__, f"{'pair':44s} {'S1 dB-ramp':>11s} {'S2 (k,m1)':>10s}"]
named = {"breaker worst pair A->B": (wp[0], wp[1]), "breaker worst pair B->A": (wp[1], wp[0]),
         "alt+ -> alt-": (h["alternating"], -h["alternating"]), "flat -> all+12": (flat, h["all+12"]),
         "all+12 -> flat": (h["all+12"], flat), "every-third-down -> flat": (h["every-third-down/0"], flat),
         "+12@1k -> flat": (h["single+12@1"] * 0 + np.eye(G.NB)[17] * 12, flat)}
for n, (a, b) in named.items():
    w1, w2 = swell(a, b); lines.append(f"{n:44s} {w1:+11.3f} {w2:+10.3f}")
def worst(pairs):
    r = np.array([swell(a, b, S[::4]) for a, b in pairs]); return r.max(0), np.percentile(r, 99, axis=0)
groups = {
  "42 preset pairs (incl. Flat/Off)": [(cur[a], cur[b]) for a, b in itertools.permutations(cur, 2)],
  "curve <-> Off, hard patterns (both ways)": [p for t in h.values() for p in ((t, flat), (flat, t))],
  "150 smooth pairs": [(a, b) for a, b in zip(G.smooth_set(rng, 150), G.smooth_set(rng, 150))],
  "200 random rough pairs (U+-12)": [(rng.uniform(-12, 12, G.NB), rng.uniform(-12, 12, G.NB)) for _ in range(200)],
  "200 Rämö pairs": list(zip(G.ramo_set(rng, 100, 100), G.ramo_set(rng, 100, 100))),
}
lines.append("\nGroups (max | p99):")
for n, pairs in groups.items():
    mx, p99 = worst(pairs); lines.append(f"  {n:42s} S1 {mx[0]:+.3f} | {p99[0]:+.3f}    S2 {mx[1]:+.3f} | {p99[1]:+.3f}")
# hill-climb each scheme's own adversarial worst (start from the breaker pair and random rough pairs)
def climb(idx, iters=250):
    best = (-99, None)
    for start in range(4):
        a, b = (wp[0].copy(), wp[1].copy()) if start == 0 else (rng.choice([-12., -6, 0, 6, 12], G.NB), rng.choice([-12., -6, 0, 6, 12], G.NB))
        v = swell(a, b, S[::5])[idx]
        for _ in range(iters):
            a2, b2 = a.copy(), b.copy(); j = rng.integers(G.NB); (a2 if rng.random() < .5 else b2)[j] = rng.choice([-12., -6, 0, 6, 12])
            v2 = swell(a2, b2, S[::5])[idx]
            if v2 >= v: a, b, v = a2, b2, v2
        if v > best[0]: best = (v, (a, b))
    return best
for idx, nm in [(0, "S1"), (1, "S2")]:
    v, (a, b) = climb(idx)
    full = swell(a, b)
    lines.append(f"\nhill-climb for {nm}'s own worst: {nm} {full[idx]:+.3f} dB (other scheme on that pair: {full[1-idx]:+.3f})")
    lines.append("   A: " + " ".join(f"{x:+.0f}" for x in a)); lines.append("   B: " + " ".join(f"{x:+.0f}" for x in b))
    np.save(f"results/adv_pair_{nm}.npy", np.vstack([a, b]))
txt = "\n".join(lines); print(txt); open("results/s2_transition_fd.txt", "w").write(txt + "\n")
