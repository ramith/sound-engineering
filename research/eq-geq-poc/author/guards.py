"""Item 7: solver guards. Flat and near-flat commands must give finite gains (the |g| < 1e-3 prototype guard), and
the C-ABI rule rejects non-finite input before the solver ever sees it."""
import numpy as np, geq2 as G
from geq import interaction_matrix
cases = {"flat": np.zeros(G.NB), "one band exactly 0 among +6": np.r_[np.full(15, 6.0), 0.0, np.full(15, 6.0)],
         "1e-9 everywhere": np.full(G.NB, 1e-9), "+12 / exactly 0 alternating": np.where(np.arange(G.NB) % 2 == 0, 12.0, 0.0)}
lines = [__doc__]
for n, t in cases.items():
    gs = G.solve_passes(t, 48000., 5); ok = all(np.all(np.isfinite(g)) for g in gs)
    lines.append(f"  {n:30s} finite through all passes: {ok}; max|g| {np.max(np.abs(gs[-1])):.3g} dB; centre err {G.centre_err(t, gs[-1], 48000.):.3f}")
# what the unguarded rebuild does: divide by a gain of exactly 0
with np.errstate(all="ignore"):
    b, a = G.bell_bilinear(G.FC, np.zeros(G.NB), 48000., G.C)
    B = (G.sos_db(b, a, G.FPTS, 48000.) / np.zeros(G.NB)[:, None]).T
lines.append(f"  an unguarded 'divide by the previous gain' rebuild after a flat solve: non-finite entries in B = {int(np.sum(~np.isfinite(B)))}/{B.size} (why the guard is in the spec)")
t = np.zeros(G.NB); t[5] = np.nan
try:
    with np.errstate(all="ignore"):
        g = G.solve_passes(t, 48000., 1)[-1]
    msg = f"finite gains = {int(np.sum(np.isfinite(g)))}/31"
except Exception as e:
    msg = f"the solve fails outright ({type(e).__name__}: {e})"
lines.append(f"  a NaN target reaching the solver: {msg} -> the C-ABI must reject non-finite input")
open("results/s7_guards.txt", "w").write("\n".join(lines) + "\n"); print("\n".join(lines))
