import numpy as np, subprocess, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from oracle import *
E = os.path.dirname(os.path.abspath(__file__))
fs = 48000.
def run(cmds, frames, hz, length):
    np.asarray(cmds,np.float32).tofile(E+'/sq.f32'); np.asarray(frames,np.float64).tofile(E+'/sf.f64')
    subprocess.run([E+'/eqseq',str(fs),E+'/sq.f32',E+'/sf.f64',str(length),str(hz),E+'/env.f64'],check=True)
    return np.fromfile(E+'/env.f64')
def steady(cmd, hz):
    r = run_cpp_design(np.asarray(cmd)[None,:], fs, np.array([hz]))[0]; return 10**(r['played'][0]/20)
probes = [20,22.4,25,28,31.5,35.5,40,45,50,56,63,71,80]
scen = {}
for band in [0,1,2,4]:
    up = [np.eye(31)[band]*g for g in range(0,13)]   # 0..+12 in 1 dB steps
    scen[f'drag-up b{band} 1dB/16.7ms'] = (up, 'step')
    scen[f'drag-down b{band}'] = (up[::-1], 'step')
    # wiggle: +12 / 0 / +12 / 0 every 50 ms
    scen[f'toggle b{band} +12/0 every 50ms'] = ([np.eye(31)[band]*(12 if i%2 else 0) for i in range(12)], 50)
for name,(cmds,mode) in scen.items():
    dt = int(fs/60) if mode=='step' else int(fs*mode/1000)
    frames = [0] + [int(0.5*fs)+i*dt for i in range(1,len(cmds))]
    length = int(frames[-1] + 1.0*fs)
    worst = (-99,None)
    for hz in probes:
        env = run(cmds, frames, hz, length)
        louder = max(steady(c, hz) for c in cmds)   # louder over ALL endpoints of the gesture
        post = env[int(0.5*fs):]
        over = 20*np.log10(post.max()/louder)
        ms3 = np.sum(post > louder*10**(1/20))/fs*1000
        if over > worst[0]: worst = (over, hz, ms3)
    print(f'{name:36s} worst overshoot over the loudest endpoint {worst[0]:+.2f} dB at {worst[1]} Hz, {worst[2]:.0f} ms above +1 dB')
