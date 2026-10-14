import numpy as np, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from oracle import *
rng = np.random.default_rng(1234)
sets = {'binary200': rng.choice([-12.,12.],(200,31)), 'uniform200': rng.uniform(-12,12,(200,31)),
        'zigzag': np.array([[12*(-1)**m for m in range(31)]],float), 'all+12': np.full((1,31),12.)}
for fs in [48000.]:
    for name, cmds in sets.items():
        rows = []
        for cmd in cmds:
            out = []
            for (it, c, bw, wt) in [(1,0.4,None,False),(5,0.4,None,False),(1,0.5,0.4,False),(5,0.5,0.4,True)]:
                g,bwf,cc = acge_paper(cmd, fs, iters=it, c=c, bw=bw, weights=wt)
                out.append(np.max(np.abs(cascade_db(g, fs, FC, bw_frac=bwf, c=cc) - cmd)))
            rows.append(out)
        rows = np.array(rows)
        print(name, 'max centre err  paper(c=.4,B=.466,1it,unweighted, no top-6 hand-tune)=%.3f  same 5it=%.3f  code-shape 1it unweighted=%.3f  code-shape 5it weighted=%.3f' % tuple(rows.max(0)))
