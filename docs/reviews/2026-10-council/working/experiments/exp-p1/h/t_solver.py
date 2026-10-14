import numpy as np, sys, os, glob
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from oracle import *
W = sys.argv[1]
rng = np.random.default_rng(1234)
NOM = np.array([20,25,31.5,40,50,63,80,100,125,160,200,250,315,400,500,630,800,1000,1250,1600,2000,2500,3150,4000,5000,6300,8000,10000,12500,16000,20000.])
def rise(hz, x): o = np.log2(hz/x); return 0.5*(1+np.sin(np.pi*np.clip(o,-.5,.5)))
def wts(hz):
    r150,r500,r2k,r6k = rise(hz,150),rise(hz,500),rise(hz,2000),rise(hz,6000)
    return np.stack([1-r150, r150-r500, r500-r2k, r2k-r6k, r6k])
tones = {'presence':[0,0,0,3.5,1],'clarity':[0,-2,0,1.5,3],'warm':[3,2,0,-1.5,-2],'loudness':[5,0,0,1,3.5],'vocal':[-2,-1.5,2,3,0],'bassBoost':[5,1,0,0,0]}
presets = {k: np.round(np.array(v)@wts(NOM)*10)/10 for k,v in tones.items()}
sets = {}
sets['presets'] = np.array(list(presets.values()))
sets['uniform1000'] = rng.uniform(-12,12,(1000,31))
sets['binary1000'] = rng.choice([-12.,12.],(1000,31))
sets['zigzag'] = np.array([[12*(-1)**m for m in range(31)],[-12*(-1)**m for m in range(31)]],float)
sets['all'] = np.array([np.full(31,12.),np.full(31,-12.)])
single = []
for b in range(31):
    for s in (12,-12): v=np.zeros(31); v[b]=s; single.append(v)
sets['single'] = np.array(single)
step = []
for b in range(30):
    v=np.full(31,-12.); v[b+1:]=12; step.append(v); step.append(-v)
sets['steps'] = np.array(step)
fx = [np.load(f).reshape(-1,31) for f in sorted(glob.glob(W+'/research/eq-geq-poc/fixtures/*.npy'))]
sets['fixtures'] = np.vstack(fx)
dense = np.exp(np.linspace(np.log(FC[0]), np.log(FC[-1]), 30*16+1))
for fs in [44100., 48000., 96000., 192000., 768000., 44000.]:
    print(f'=== fs={fs:.0f}')
    for name, cmds in sets.items():
        grid = np.concatenate([FC, MID, dense])
        res = run_cpp_design(cmds, fs, grid)
        rb_err = 0; ce = []; me = []; enc = 0; k0e = 0; maxg = 0; gn_ratio = []; paper_ce = []
        for i,(cmd, r) in enumerate(zip(cmds, res)):
            assert r['ok'], (name, i)
            orc = cascade_db(r['gains'], fs, grid)
            rb_err = max(rb_err, np.max(np.abs(orc - r['played'])))
            G = 20*np.log10(1 + r['m1']/r['k'])
            enc = max(enc, np.max(np.abs(G - r['gains'])))
            w = 2*np.pi*FC/fs; k0 = 2*np.tan(0.2*w)/np.sin(w)
            A = 10**(r['gains']/40)
            k0e = max(k0e, np.max(np.abs(r['k']*A/k0 - 1)))
            ce.append(np.max(np.abs(r['played'][:31] - cmd)))
            me.append(np.max(np.abs(r['played'][31:61] - 0.5*(cmd[:-1]+cmd[1:]))))
            maxg = max(maxg, np.max(np.abs(r['gains'])))
            if name in ('presets','zigzag','all','fixtures') or (i < 40 and name in ('uniform1000','binary1000','steps')):
                t = target61(cmd); played61 = np.empty(61); played61[0::2]=r['played'][:31]; played61[1::2]=r['played'][31:61]
                c_cpp = np.sum(W2*(played61-t)**2)
                g_gn, c_gn = gauss_newton(cmd, fs, g0=r['gains'].copy())
                gn_ratio.append(c_cpp / max(c_gn,1e-30))
                gp,_,_ = acge_paper(cmd, fs)
                paper_ce.append(np.max(np.abs(cascade_db(gp, fs, FC) - cmd)))
        print(f'{name:12s} n={len(cmds):4d} readback-vs-oracle max {rb_err:.2e} dB | gain-encode {enc:.1e} | k*A/k0-1 {k0e:.1e} | '
              f'centre err max {max(ce):.3f} p99 {np.percentile(ce,99):.3f} | mid err max {max(me):.3f} | max|g| {maxg:.1f} | '
              f'cost/GN-opt max {max(gn_ratio) if gn_ratio else float("nan"):.4f} | paper-ACGE(c=.4,1it) centre max {max(paper_ce) if paper_ce else float("nan"):.3f}')
