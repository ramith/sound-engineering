# Independent check of TruePeakKernel (8x, 192-tap Kaiser b=8, centre 95.5) vs ideal true peak.
import numpy as np
L=8; NT=24; N=L*NT; beta=8.0
n=np.arange(N); c=(N-1)/2; d=n-c
h=np.sinc(d/L)*np.kaiser(N,beta)        # scale L*2fc = 1 ; np.sinc = sin(pi x)/(pi x)
# frequency response of prototype at 8x rate, normalised so DC gain per phase ~1
H=lambda f: np.abs(np.sum(h*np.exp(-2j*np.pi*f*n/L)))/L*1.0  # f in base-rate cycles/sample
dc=np.sum(h)/L
print("per-phase DC gains:", [round(np.sum(h[p::L]),6) for p in range(L)])
for f in [0.25,0.35,0.40,0.42,0.4535,0.47,0.5,0.55,0.6,0.65,0.7,0.8,1.0,1.5]:
    print(f"|H|({f:.4f} fs) = {20*np.log10(H(f)/dc+1e-30):8.2f} dB")
# image rejection: worst stopband for f in [0.5+?] ... images of a tone at f appear at k - f, k+ f (k=1..7)
fs_grid=np.linspace(0.55,4.0,20000)
sb=max(20*np.log10(H(f)/dc) for f in fs_grid)
print("max |H| for f in [0.55,4.0]·fs (stopband) =", round(sb,2),"dB")
# true-peak readout for sines: emulate phasePeak over all n
coeffs=np.array([h[p::L] for p in range(L)])   # phase p, tap k = h[p+kL]
def tp_read(x):
    # y_p[n] = sum_k h[p+kL] x[n-k]
    out=0
    for p in range(L):
        y=np.convolve(x,coeffs[p])[NT:len(x)]
        out=max(out,np.max(np.abs(y)))
    return out
rng=np.random.default_rng(1)
for fsr,fmax in [(44100,20000),(48000,20000),(48000,22000),(44100,21000)]:
    worst_under=0; worst_over=0; wf=None
    for f in np.concatenate([np.linspace(20,fmax,400)]):
        for ph in rng.uniform(0,2*np.pi,8):
            t=np.arange(4096); x=np.cos(2*np.pi*f/fsr*t+ph)
            r=20*np.log10(tp_read(x))
            if r<worst_under: worst_under=r; wf=f
            worst_over=max(worst_over,r)
    print(f"fs={fsr} f<= {fmax}: worst under-read {worst_under:.3f} dB at {wf:.0f} Hz; worst over-read {worst_over:.3f} dB")
# libebur128 4x 49-tap Hann for comparison
def ebur_coeffs(taps=49,factor=4):
    j=np.arange(taps); m=j-(taps-1)/2
    cc=np.where(np.abs(m)<1e-6,1.0,np.sinc(m/factor))*0.5*(1-np.cos(2*np.pi*j/(taps-1)))
    return cc
he=ebur_coeffs()
def tp_ebur(x):
    out=0
    for p in range(4):
        y=np.convolve(x,he[p::4])[13:len(x)]
        out=max(out,np.max(np.abs(y)))
    return out
for fsr,fmax in [(44100,20000),(48000,20000)]:
    wu=0;wo=0;wf=None
    for f in np.linspace(20,fmax,400):
        for ph in rng.uniform(0,2*np.pi,8):
            t=np.arange(4096); x=np.cos(2*np.pi*f/fsr*t+ph)
            r=20*np.log10(tp_ebur(x)); 
            if r<wu: wu=r; wf=f
            wo=max(wo,r)
    print(f"libebur128 4x49: fs={fsr}: worst under {wu:.3f} dB at {wf:.0f} Hz, worst over {wo:.3f}")
