# Today's C++ designer vs the research reference (geq2.solve_passes(t, fs, 5)[-1]) on 600 curves × 4 rates.
import numpy as np, sys, os
W = sys.argv[1]
sys.path.insert(0, W + '/research/eq-geq-poc/author')
import geq2
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from oracle import run_cpp_design, FC
rng = np.random.default_rng(99)
cmds = np.vstack([rng.uniform(-12,12,(200,31)), rng.choice([-12.,0.,12.],(200,31)), np.round(rng.uniform(-12,12,(200,31)))])
for fs in [44100., 48000., 96000., 192000.]:
    res = run_cpp_design(cmds, fs, FC)
    dg = 0; dce = 0
    for cmd, r in zip(cmds, res):
        g_ref = np.asarray(geq2.solve_passes(cmd.astype(np.float32).astype(np.float64), fs, 5)[-1])
        dg = max(dg, np.max(np.abs(g_ref - r['gains'])))
    print(f'fs {fs:.0f}: max |C++ gain - geq2 reference gain| over {len(cmds)} curves = {dg:.2e} dB')
