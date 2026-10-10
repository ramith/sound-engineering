"""Item 2 fairness check: does a slow ramp also rescue S1? S1 vs S2 at tau 40 ms on the pinned adversarial pairs."""
import numpy as np, trans_td as T, geq2 as G
from trans_td2 import ovs
h = G.hard_set(); wp = np.load("../../review/breaker/worst_pair.npy"); a1 = np.load("results/adv_pair_S1.npy"); a2 = np.load("results/adv_pair_S2.npy")
P = np.geomspace(25, 18000, 48); lines = [__doc__]
for nm, (a, b) in {"breaker A->B": (wp[0], wp[1]), "breaker B->A": (wp[1], wp[0]), "S1-adversarial": (a1[0], a1[1]), "S2-adversarial": (a2[0], a2[1])}.items():
    A, B = T.ep(a), T.ep(b); r = [ovs([(0.0, A), (T.T0, B)], P, mode=m, tau=0.040) for m in (0, 1)]
    lines.append(f"  {nm:16s} S1 tau40 {r[0][0]:+6.2f}/{r[0][2]:+5.2f}   S2 tau40 {r[1][0]:+6.2f}/{r[1][2]:+5.2f}  (local/peak dB)")
open("results/s2f_tau40_both.txt", "w").write("\n".join(lines) + "\n"); print("\n".join(lines))
