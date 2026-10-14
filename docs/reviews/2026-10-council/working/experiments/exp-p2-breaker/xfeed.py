import numpy as np
fs=48000.0
f=np.array([50,100,300,700,1000,2000,4000,8000,16000.0])
z=np.exp(1j*2*np.pi*f/fs)
def as_cf(alpha,fc,D=15):
    gD=1/(1+alpha); gC=alpha/(1+alpha); p=np.exp(-2*np.pi*fc/fs)
    H=(1-p)/(1-p/z)*z**(-D)
    direct=gD*np.ones_like(z); cross=gC*H
    return direct,cross
def bs2b(fcut,feed_db):
    level=feed_db
    GB_lo=level*-5/6-3; GB_hi=level/6-3
    G_lo=10**(GB_lo/20); G_hi=1-10**(GB_hi/20)
    Fc_hi=fcut*2**((GB_lo-20*np.log10(G_hi))/12)
    x=np.exp(-2*np.pi*fcut/fs); a0_lo=G_lo*(1-x); b1_lo=x
    x2=np.exp(-2*np.pi*Fc_hi/fs); a0_hi=1-G_hi*(1-x2); a1_hi=-x2; b1_hi=x2
    gain=1/(1-G_hi+G_lo)
    lo=a0_lo/(1-b1_lo/z); hi=(a0_hi+a1_hi/z)/(1-b1_hi/z)
    return gain*hi, gain*lo
def db(x): return 20*np.log10(np.abs(x))
print("freq:            ", " ".join(f"{int(v):>6d}" for v in f))
for name,(d,c) in {"AS Relaxed a=.335 fc650":as_cf(.335,650),"AS Default a=.355 fc700":as_cf(.355,700),"AS Strong  a=.501 fc700":as_cf(.501,700),
                   "bs2b Jmeier 650/9.5":bs2b(650,9.5),"bs2b Default 700/4.5":bs2b(700,4.5),"bs2b Cmoy 700/6.0":bs2b(700,6.0)}.items():
    print(name)
    print("  centre (L=R) sum dB ", " ".join(f"{v:6.2f}" for v in db(d+c)))
    print("  hard-L ipsi dB      ", " ".join(f"{v:6.2f}" for v in db(d)))
    print("  hard-L contra dB    ", " ".join(f"{v:6.2f}" for v in db(c)))
