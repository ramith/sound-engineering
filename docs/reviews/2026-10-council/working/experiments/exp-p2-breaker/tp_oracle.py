# Independent true-peak oracle: band-limited (periodic-FFT) interpolation x32 on overlapping
# segments with discarded margins. Exact for band-limited content away from segment edges.
import numpy as np, sys, glob, os
def true_peak(x, up=32, seg=16384, margin=2048):
    n = len(x); best = 0.0; pos = 0
    start = 0
    while start < n:
        a = max(0, start - margin); b = min(n, start + seg + margin)
        s = x[a:b].astype(np.float64)
        L = len(s)
        S = np.fft.rfft(s)
        Z = np.zeros(L*up//2+1, dtype=complex); Z[:len(S)] = S
        if L % 2 == 0: Z[len(S)-1] *= 0.5  # split Nyquist bin
        y = np.fft.irfft(Z, L*up) * up
        lo = (start - a)*up; hi = lo + (min(n, start+seg) - start)*up
        if a == 0: lo = margin*up if start == 0 else lo
        seg_y = np.abs(y[lo:hi])
        if len(seg_y):
            i = int(np.argmax(seg_y))
            if seg_y[i] > best: best = seg_y[i]; pos = (lo + i)/up + a
        start += seg
    return 20*np.log10(best + 1e-30), pos
if __name__ == "__main__":
    tag = sys.argv[1]; skip = float(sys.argv[2]); fs = int(sys.argv[3]); ceil_db = float(sys.argv[4])
    print(f"{'signal':28s} {'outTP_dBTP':>10s} {'over_ceiling_dB':>15s} {'at_s':>7s}")
    for f in sorted(glob.glob(f"lim_{tag}_*.f32")):
        d = np.fromfile(f, dtype=np.float32).reshape(-1, 2)
        k = int(skip*fs)
        tp = max(true_peak(d[k:, 0])[0], true_peak(d[k:, 1])[0])
        tp0, p0 = true_peak(d[k:, 0])
        print(f"{os.path.basename(f)[len('lim_'+tag)+1:-4]:28s} {tp:10.3f} {tp-ceil_db:15.3f} {(p0+k)/fs:7.3f}")
