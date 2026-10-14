import numpy as np, sys, os, subprocess
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from oracle import *
W = sys.argv[1]
rng = np.random.default_rng(7)
cmds = {'binaryWorst': np.load(W+'/research/eq-geq-poc/fixtures/worst_cmd_44100.npy'),
        'zigzag': np.array([12*(-1)**m for m in range(31)],float),
        'all+12': np.full(31,12.), 'b0+12': np.eye(31)[0]*12, 'b30-12': -np.eye(31)[30]*12,
        'uniform': rng.uniform(-12,12,31)}
for fs, N in [(44100,2**19),(48000,2**19),(192000,2**21),(384000,2**22)]:
    for ch in [1,2,3,6,8]:
        worst = 0; chdiff = 0
        for name, cmd in cmds.items():
            if ch not in (2,8) and name not in ('zigzag','b0+12'): continue
            cmd.astype(np.float32).tofile(E+'/cmd1.f32')
            subprocess.run([E+'/eqh','ir',str(fs),str(ch),'512',str(N),E+'/cmd1.f32',E+'/ir.f32'],check=True)
            raw = np.fromfile(E+'/ir.f32',np.float32)
            # blocks of 512 per channel interleaved per block
            nb = N//512; raw = raw.reshape(nb, ch, 512).transpose(1,0,2).reshape(ch, N).astype(np.float64)
            irs = raw / (0.1*(np.arange(ch)+1))[:,None]
            chdiff = max(chdiff, np.max(np.abs(irs - irs[0])))
            H = np.fft.rfft(irs[0]); f = np.fft.rfftfreq(N, 1/fs)
            sel = (f >= 15) & (f <= min(0.98*fs/2, 21000))
            meas = 20*np.log10(np.abs(H[sel]))
            # design gains from the harness's design mode
            res = run_cpp_design(cmd[None,:], fs, np.array([1000.]))[0]
            orc = cascade_db(res['gains'], fs, f[sel])
            e = np.max(np.abs(meas-orc)); worst = max(worst, e)
            tail = np.max(np.abs(irs[0][-1000:]))
        print(f'fs={fs} ch={ch}: max |IR-measured - oracle| = {worst:.2e} dB; max channel mismatch {chdiff:.1e}; last-1000 tail {tail:.1e}')
