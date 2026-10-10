"""Item 2: S2 ramp-time sweep on the pinned adversarial pairs, and a realistic drag (TD overshoot, dB: local [Hz] / peak)."""
import numpy as np, trans_td as T, geq2 as G
from trans_td2 import ovs
flat = np.zeros(G.NB); h = G.hard_set()
wp = np.load("../../review/breaker/worst_pair.npy"); a1 = np.load("results/adv_pair_S1.npy"); a2 = np.load("results/adv_pair_S2.npy")
pairs = {"breaker A->B": (wp[0], wp[1]), "breaker B->A": (wp[1], wp[0]), "S1-adversarial": (a1[0], a1[1]),
         "S2-adversarial": (a2[0], a2[1]), "alt+ -> alt-": (h["alternating"], -h["alternating"])}
P = np.geomspace(25, 18000, 48)
lines = [__doc__, f"{'pair':18s} " + " ".join(f"{'tau '+str(t)+' ms':>22s}" for t in (10, 20, 40, 60))]
for nm, (a, b) in pairs.items():
    A, B = T.ep(a), T.ep(b)
    r = [ovs([(0.0, A), (T.T0, B)], P, tau=t / 1000) for t in (10, 20, 40, 60)]
    lines.append(f"{nm:18s} " + " ".join(f"{x[0]:+6.2f} [{x[1]:5.0f}]/{x[2]:+5.2f}" for x in r)); print(lines[-1], flush=True)
# realistic drag: Warm, band 125 Hz (idx 8) raised to +12 at 120 Hz in 0.5 dB steps, neighbours follow (stroke-start rule)
w = G.PRESETS["Warm"].copy(); start = w.copy(); ev = [(0.0, T.ep(w))]; t = T.T0; base = start[8]
for v in np.arange(base + 0.5, 12.01, 0.5):
    c = start.copy(); c[8] = v
    for o, wt in [(1, .75), (2, .25)]:
        for sg in (-1, 1):
            j = 8 + o * sg; c[j] = np.clip(start[j] + (v - start[j]) * wt, -12, 12)
    ev.append((round(t, 6), T.ep(c))); t += 1 / 120
for mode, nm in [(0, "S1"), (1, "S2")]:
    x = ovs(ev, P, mode=mode)
    lines.append(f"realistic drag Warm 125 Hz -> +12 ({len(ev)-1} steps @120 Hz), {nm}: local {x[0]:+.2f} [{x[1]:.0f}] / peak {x[2]:+.2f}"); print(lines[-1])
open("results/s2e_tau_sweep_drag.txt", "w").write("\n".join(lines) + "\n")
