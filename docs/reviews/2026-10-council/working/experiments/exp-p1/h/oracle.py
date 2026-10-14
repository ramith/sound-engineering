# Panel P1 independent EQ oracle. Written from the ACGE/Orfanidis biquad equations (DAFx-17
# "Quest for the best GEQ" eq. (1)-(2)), NOT from the repo's SVF code.
import numpy as np, subprocess, os, sys
E = os.path.dirname(os.path.abspath(__file__))
FC = 10.0 ** (1.3 + 0.1 * np.arange(31))
MID = np.sqrt(FC[:-1] * FC[1:])
PTS = np.empty(61); PTS[0::2] = FC; PTS[1::2] = MID

def bell_ba(gdb, f0, fs, bw_frac=0.4, c=0.5):
    w = 2 * np.pi * f0 / fs
    G = 10 ** (gdb / 20.0)
    if abs(gdb) < 1e-15:
        return np.array([1.0, -2*np.cos(w), 1.0]), np.array([1.0, -2*np.cos(w), 1.0])
    GB = G ** c
    beta = np.sqrt(abs(GB**2 - 1) / abs(G**2 - GB**2)) * np.tan(bw_frac * w / 2)
    b = np.array([1 + G * beta, -2 * np.cos(w), 1 - G * beta])
    a = np.array([1 + beta, -2 * np.cos(w), 1 - beta])
    return b, a

def bell_db(gdb, f0, fs, f, **kw):
    b, a = bell_ba(gdb, f0, fs, **kw)
    z = np.exp(-1j * 2 * np.pi * np.asarray(f) / fs)
    H = (b[0] + b[1] * z + b[2] * z * z) / (a[0] + a[1] * z + a[2] * z * z)
    return 20 * np.log10(np.abs(H))

def cascade_db(gains, fs, f, **kw):
    return sum(bell_db(g, f0, fs, f, **kw) for g, f0 in zip(gains, FC))

def target61(cmd):
    t = np.empty(61); t[0::2] = cmd; t[1::2] = 0.5 * (cmd[:-1] + cmd[1:]); return t

W2 = np.where(np.arange(61) % 2 == 0, 1.0, 0.25)

def gauss_newton(cmd, fs, g0=None, iters=60, **kw):
    """Minimise sum w^2 (L(f_p;g) - t_p)^2 on the TRUE cascade response (no basis approximation)."""
    t = target61(cmd); g = np.array(cmd, float) * 1.0 if g0 is None else g0.copy()
    lam = 1e-6
    def resid(g): return cascade_db(g, fs, PTS, **kw) - t
    r = resid(g); cost = np.sum(W2 * r * r)
    for _ in range(iters):
        J = np.empty((61, 31)); h = 1e-6
        for m in range(31):
            gp = g.copy(); gp[m] += h
            J[:, m] = (bell_db(gp[m], FC[m], fs, PTS, **kw) - bell_db(g[m], FC[m], fs, PTS, **kw)) / h
        A = J.T @ (W2[:, None] * J); bvec = J.T @ (W2 * r)
        while True:
            step = np.linalg.solve(A + lam * np.diag(np.diag(A)), -bvec)
            gn = g + step; rn = resid(gn); cn = np.sum(W2 * rn * rn)
            if cn < cost: g, r, cost = gn, rn, cn; lam = max(lam / 10, 1e-12); break
            lam *= 10
            if lam > 1e8: return g, cost
        if np.max(np.abs(step)) < 1e-10: break
    return g, cost

def acge_paper(cmd, fs, iters=1, c=0.4, bw=None, weights=False):
    """ACGE as published (DAFx-17 third-octave): prototype 17 dB, pseudo-inverse, `iters` re-solves."""
    t = target61(cmd)
    bwf = (2 ** (1 / 6) - 2 ** (-1 / 6)) if bw is None else bw
    def basis(gp):
        return np.stack([bell_db(gp[m], FC[m], fs, PTS, bw_frac=bwf, c=c) / gp[m] for m in range(31)], 1)
    Wd = np.sqrt(W2) if weights else np.ones(61)
    B = basis(np.full(31, 17.0)); g = np.linalg.lstsq(Wd[:, None] * B, Wd * t, rcond=None)[0]
    for _ in range(iters):
        gp = np.where(np.abs(g) < 1e-3, np.where(g >= 0, 1e-3, -1e-3), g)
        B = basis(gp); g = np.linalg.lstsq(Wd[:, None] * B, Wd * t, rcond=None)[0]
    return g, bwf, c

def run_cpp_design(cmds, fs, grid):
    cmds = np.asarray(cmds, np.float32).reshape(-1, 31)
    cmds.tofile(E + '/cmds.f32'); np.asarray(grid, np.float64).tofile(E + '/grid.f64')
    subprocess.run([E + '/eqh', 'design', repr(float(fs)), E + '/cmds.f32', E + '/grid.f64', E + '/out.f64'], check=True)
    raw = np.fromfile(E + '/out.f64')
    rec = 1 + 31 * 4 + len(grid) + 32
    raw = raw.reshape(-1, rec)
    out = []
    for r in raw:
        d = dict(ok=r[0] == 1, gains=r[1:32], k=r[32:63], m1=r[63:94], g=r[94:125],
                 played=r[125:125 + len(grid)], tau=r[125 + len(grid):125 + len(grid) + 31], gtau=r[-1])
        out.append(d)
    return out
