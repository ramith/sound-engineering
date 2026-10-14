import numpy as np
fs=48000.0
def bs2b(fc,feed_db):
    GB_lo=feed_db*-5/6-3; GB_hi=feed_db/6-3
    G_lo=10**(GB_lo/20); G_hi=1-10**(GB_hi/20)
    Fc_hi=fc*2**((GB_lo-20*np.log10(G_hi))/12)
    x=np.exp(-2*np.pi*fc/fs); a0_lo=G_lo*(1-x); b1_lo=x
    xh=np.exp(-2*np.pi*Fc_hi/fs); a0_hi=1-G_hi*(1-xh); a1_hi=-xh; b1_hi=xh
    gain=1/(1-G_hi+G_lo)
    def H(f):
        z=np.exp(2j*np.pi*f/fs)
        lo=a0_lo/(1-b1_lo/z); hi=(a0_hi+a1_hi/z)/(1-b1_hi/z)
        return hi*gain, lo*gain
    return H
def app(fc,alpha):
    gD=1/(1+alpha); gC=alpha/(1+alpha); p=np.exp(-2*np.pi*fc/fs); D=round(0.0003178*fs)
    def H(f):
        z=np.exp(2j*np.pi*f/fs)
        return gD+0*z, gC*(1-p)/(1-p/z)*z**(-D)
    return H
def gd(Hf,f,eps=1.0):
    ph=lambda ff: np.angle(Hf(ff))
    return -(np.unwrap([ph(f-eps),ph(f+eps)])[1]-np.unwrap([ph(f-eps),ph(f+eps)])[0])/(2*np.pi*2*eps)
cases=[("bs2b Jmeier 650/9.5",bs2b(650,9.5)),("app Relaxed 650/a=.335",app(650,0.335)),
       ("bs2b Cmoy 700/6.0",bs2b(700,6.0)),("app Strong 700/a=.501",app(700,0.501)),
       ("bs2b Default 700/4.5",bs2b(700,4.5)),("app 'Bauer' 700/a=.355",app(700,0.355))]
fr=[50,200,500,1000,2000,4000,8000,16000]
for name,H in cases:
    mono=[20*np.log10(abs(sum(H(f)))) for f in fr]
    direct=[20*np.log10(abs(H(f)[0])) for f in fr]
    cross=[20*np.log10(abs(H(f)[1])) for f in fr]
    itd=(gd(lambda ff:H(ff)[1],100)-gd(lambda ff:H(ff)[0],100))*1e3
    print(f"{name:26s} ITD@100Hz={itd:5.3f} ms")
    print("   f(Hz):     "+" ".join(f"{f:7d}" for f in fr))
    print("   mono(dB):  "+" ".join(f"{v:7.2f}" for v in mono))
    print("   direct(dB):"+" ".join(f"{v:7.2f}" for v in direct))
    print("   cross(dB): "+" ".join(f"{v:7.2f}" for v in cross))
