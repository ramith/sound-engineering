# Synthesize EBU Tech 3341 (2023) Table 1 minimum-requirement signals (cases 1-6, 9, 12, 13, 15-23) at fs.
import numpy as np, sys, os
from scipy.signal import resample_poly
out=sys.argv[1]; fs=int(sys.argv[2])
def tone(db, sec, f=1000.0, ph0=0.0):
    n=int(round(sec*fs)); t=np.arange(n)/fs
    return (10**(db/20))*np.sin(2*np.pi*f*t+ph0)
def seq(parts, f=1000.0):
    # phase-continuous concatenation
    x=[]; ph=0.0
    for db,sec in parts:
        n=int(round(sec*fs)); t=np.arange(n)/fs
        x.append((10**(db/20) if db is not None else 0.0)*np.sin(2*np.pi*f*t+ph)); ph+=2*np.pi*f*n/fs
    return np.concatenate(x)
def write(name, chans):
    a=np.stack(chans,axis=1).astype(np.float32); a.tofile(os.path.join(out,f"{name}_{fs}_{a.shape[1]}ch.f32"))
s=tone(-23,20); write("c01",[s,s])
s=tone(-33,20); write("c02",[s,s])
s=seq([(-36,10),(-23,60),(-36,10)]); write("c03",[s,s])
s=seq([(-72,10),(-36,10),(-23,60),(-36,10),(-72,10)]); write("c04",[s,s])
s=seq([(-26,20),(-20,20.1),(-26,20)]); write("c05",[s,s])
L=tone(-28,20); C=tone(-24,20); S=tone(-30,20); Z=np.zeros_like(L)
write("c06",[L,L,C,Z,S,S])   # MPEG_5_1_A order L R C LFE Ls Rs (LFE silent)
s=seq([(-20,1.34),(-30,1.66)]*5); write("c09",[s,s])
s=seq([(-20,0.18),(-30,0.22)]*25); write("c12",[s,s])
for i in range(20):
    s=seq([(None,i*0.02),(-23,0.4),(None,1.0)]); write(f"c13_{i:02d}",[s,s])
def fade(x,ms=10):
    n=int(ms*fs/1000); w=np.ones(len(x)); w[:n]=np.linspace(0,1,n); w[-n:]=np.linspace(1,0,n); return x*w
def tpsine(f,amp,phdeg,sec=1.0):
    n=int(sec*fs); t=np.arange(n)/fs; return fade(amp*np.sin(2*np.pi*f*t+np.deg2rad(phdeg)))
for c,(f,a,p) in {15:(fs/4,0.5,0),16:(fs/4,0.5,45),17:(fs/6,0.5,60),18:(fs/8,0.5,67.5),19:(fs/4,1.41,45)}.items():
    s=tpsine(f,a,p); write(f"c{c}",[s,s])
# 20-23: synthesized at 4fs: fs/6 sine amp .5 with ONE period of fs/4 sine amp 1.0, continuous in phase; lowpass + downsample with offsets
F=4*fs; n=int(1.0*F); t=np.arange(n)/F
x=0.5*np.sin(2*np.pi*(fs/6)*t)
# insert one period of fs/4 (16 samples at 4fs) starting at a zero crossing of the fs/6 tone at the mid point
p6=int(F/(fs/6)); mid=(n//2//p6)*p6; L4=int(F/(fs/4))
x[mid:mid+L4]=1.0*np.sin(2*np.pi*(fs/4)*np.arange(L4)/F)
w=np.ones(n); m=int(0.01*F); w[:m]=np.linspace(0,1,m); w[-m:]=np.linspace(1,0,m); x*=w
for k,off in zip((20,21,22,23),(0,1,2,3)):
    y=resample_poly(x[off:],1,4,window=('kaiser',12.0)); write(f"c{k}",[y,y])
