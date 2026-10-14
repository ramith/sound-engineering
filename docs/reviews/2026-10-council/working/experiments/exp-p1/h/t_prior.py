import numpy as np, subprocess, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from oracle import *
E = os.path.dirname(os.path.abspath(__file__))
rng = np.random.default_rng(5)
for fs in (44100, 48000, 96000, 192000):
    n = fs*30
    X = np.fft.rfft(rng.standard_normal(n)); f = np.fft.rfftfreq(n, 1/fs); X[1:] /= np.sqrt(f[1:]); X[0] = 0
    x = np.fft.irfft(X, n); x = 0.05*x/np.sqrt(np.mean(x**2))
    np.asarray([x, x], np.float32).tofile(E+'/sig.f32')
    cmds = np.vstack([rng.uniform(-12,12,(30,31)), np.eye(31)[[0,3,10,20,28,30]]*12, -np.eye(31)[[0,3,10,20,28,30]]*12]).astype(np.float32)
    cmds.tofile(E+'/pc.f32')
    subprocess.run([E+'/proh2', str(fs), str(fs), '2', E+'/sig.f32', E+'/pc.f32', E+'/pr.f64'], check=True)
    r = np.fromfile(E+'/pr.f64')[2:].reshape(-1,3)
    d = r[:,2] - r[:,1]
    print(f'fs {fs}: prior-vs-real-pink ΔL difference over {len(cmds)} curves: max {np.max(np.abs(d)):.3f} dB, mean {np.mean(np.abs(d)):.3f} dB')
