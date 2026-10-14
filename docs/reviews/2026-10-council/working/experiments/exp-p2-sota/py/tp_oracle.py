import numpy as np, sys, glob, os
from scipy.signal import resample_poly
d=sys.argv[1]
def tp(x, up=32):
    y=resample_poly(x.astype(np.float64), up, 1, window=('kaiser', 14.0))   # long, high-stopband interpolator
    return 20*np.log10(np.max(np.abs(y))+1e-30)
for f in sorted(glob.glob(os.path.join(d,'out_*.f32'))):
    x=np.fromfile(f,dtype=np.float32)
    fs=int(f.rsplit('_',1)[1].split('.')[0])
    x=x[fs//10:]   # skip first 100 ms
    xi=np.fromfile(f.replace('out_','in_'),dtype=np.float32)
    print(f"{os.path.basename(f):38s} in TP={tp(xi):7.2f} dBTP  out TP={tp(x):7.3f} dBTP   (published ceiling -1.000, working -1.270)")
