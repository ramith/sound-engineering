import numpy as np, subprocess, os, sys
from scipy.signal import lfilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from oracle import *
E = os.path.dirname(os.path.abspath(__file__))
fs = 48000; T = 40
rng = np.random.default_rng(11)
n = fs*T; t = np.arange(n)/fs
# BS.1770-4 Table 1/2 coefficients at 48 kHz (from the Recommendation text)
B1=[1.53512485958697,-2.69169618940638,1.19839281085285]; A1=[1.0,-1.69065929318241,0.73248077421585]
B2=[1.0,-2.0,1.0]; A2=[1.0,-1.99004745483398,0.99007225036621]
def kw(x): return lfilter(B2,A2,lfilter(B1,A1,x))
def blocks_z(xs):
    y = [kw(c.astype(np.float64)) for c in xs]
    L = 19200; H = 4800; nb = (len(y[0]) - L)//H + 1
    z = np.array([sum(np.mean(c[j*H:j*H+L]**2) for c in y) for j in range(nb)])
    return z, y
def gated(z):
    za = z[z > 10**((-70+0.691)/10)]
    if len(za)==0: return -np.inf
    rel = np.mean(za)*0.1
    zg = z[(z > max(rel, 10**((-70+0.691)/10)))]
    return -0.691 + 10*np.log10(np.mean(zg))
def lufs(xs): return gated(blocks_z(xs)[0])
def pink(n):
    X = np.fft.rfft(rng.standard_normal(n)); f = np.fft.rfftfreq(n, 1/fs); X[1:] /= np.sqrt(f[1:]); X[0]=0
    x = np.fft.irfft(X, n); return x/np.sqrt(np.mean(x**2))
def edges():
    e=[]; i=0
    while 20*2**(i/24) < fs/2: e.append(20*2**(i/24)); i+=1
    return np.array(e)
EDG = edges(); NB = len(EDG)+1
lo = np.concatenate([[0],EDG]); hi = np.concatenate([EDG,[fs/2]]); CEN = np.sqrt(np.maximum(lo,10)*hi)
def py_profile(y, window=None):
    L=19200; H=4800; N=32768; nb=(len(y[0])-L)//H+1
    f = np.arange(N//2+1)*fs/N; band = np.searchsorted(EDG, f, side='right')
    P = np.zeros((nb, NB))
    wv = np.ones(L) if window is None else window(L)
    for j in range(nb):
        S = np.zeros(N//2+1); z = 0
        for c in y:
            seg = c[j*H:j*H+L]; z += np.mean(seg**2)
            X = np.abs(np.fft.rfft(seg*wv, N))**2; X[1:-1]*=2; S += X
        if window is not None: S = S/np.sum(S)*z if np.sum(S)>0 else S
        else: S = S/(N*L)
        P[j] = np.bincount(band, weights=S, minlength=NB)
    return P
def py_predict(P, respdb):
    g = 10**(respdb/10)
    zp = P.sum(1); zw = P@g
    lp = gated(zp); lw = gated(zw)
    return np.clip(lw-lp, respdb.min(), respdb.max())
def save(xs): np.asarray(xs, np.float32).tofile(E+'/sig.f32')
progs = {}
progs['pink steady'] = [0.1*pink(n), 0.1*pink(n)]
env = 10**((-10*np.sin(2*np.pi*t/7)**2)/20); q = np.where((t>20)&(t<28), 0.01, 1.0)
progs['pink dynamic+quiet'] = [0.1*pink(n)*env*q, 0.1*pink(n)*env*q]
for f0 in (31.5, 50.0, 63.0):
    s = 0.25*np.sin(2*np.pi*f0*t); progs[f'sine {f0} Hz + pink -30'] = [s+0.01*pink(n), s+0.01*pink(n)]
kick = np.zeros(n); per = fs//2; tt = np.arange(per)/fs
k1 = 0.5*np.sin(2*np.pi*(45+60*np.exp(-tt*30))*tt)*np.exp(-tt*4)
for i in range(0, n-per, per): kick[i:i+per] += k1
hat = rng.standard_normal(n); hat = lfilter([1,-1],[1],hat)*0.02*(np.sin(2*np.pi*4*t)>0.9)
progs['808 kicks + hats'] = [kick+hat, kick+hat]
bass = 0.3*np.sin(2*np.pi*55*t)*(np.floor(t/2)%2==0); treb = 0.003*lfilter([1,-1],[1],rng.standard_normal(n))*(np.floor(t/2)%2==1)
progs['alt loud bass / quiet treble'] = [bass+treb, bass+treb]
cmds = {'zigzag':np.array([12*(-1)**m for m in range(31)],float), 'b4(50Hz)+12':np.eye(31)[4]*12, 'b4(50Hz)-12':-np.eye(31)[4]*12,
        'b2(31.5)+12':np.eye(31)[2]*12, 'bassBoost':np.array([5,5,5,5,5,5,5,5,5,4.9,4.3,3,1.7,1.1,1,1,1,0.9,0.5,0.2,0,0,0,0,0,0,0,0,0,0,0],float),
        'treble+12 (b24..30)':np.concatenate([np.zeros(24),np.full(7,12.)]), 'uniform':rng.uniform(-12,12,31)}
C = np.array(list(cmds.values()), np.float32)
print(f'{"programme":30s} {"curve":20s} {"true dL":>8s} {"C++ pred":>8s} {"py-rect":>8s} {"py-hann":>8s}  err C++ / hann')
for pname, xs in progs.items():
    save(xs); C.tofile(E+'/pc.f32')
    subprocess.run([E+'/proh', str(fs), str(fs), '2', E+'/sig.f32', E+'/pc.f32', E+'/pred.f64'], check=True)
    r = np.fromfile(E+'/pred.f64'); src = r[0]; res = r[2:].reshape(-1,3)
    l0 = lufs(xs)
    _, y = blocks_z(xs)
    Pr = py_profile(y); Ph = py_profile(y, np.hanning)
    for (cname, cmd), (ok, dl, dl4) in zip(cmds.items(), res):
        np.asarray(cmd, np.float32).tofile(E+'/c1.f32')
        subprocess.run([E+'/eqh','apply',str(fs),'2',E+'/sig.f32',E+'/c1.f32',E+'/sigo.f32'],check=True)
        yo = np.fromfile(E+'/sigo.f32',np.float32).reshape(2,-1)
        true = lufs([yo[0],yo[1]]) - l0
        g = run_cpp_design(cmd[None,:], fs, CEN)[0]['played']
        pr = py_predict(Pr, g); ph = py_predict(Ph, g)
        print(f'{pname:30s} {cname:20s} {true:+8.3f} {dl:+8.3f} {pr:+8.3f} {ph:+8.3f}  {dl-true:+.3f} / {ph-true:+.3f}   (src {src:.2f} vs mine {l0:.2f})')
