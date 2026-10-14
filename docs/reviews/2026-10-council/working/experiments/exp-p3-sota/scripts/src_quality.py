# SRC quality: AVAudioConverter (production streaming pattern, via out/src_dump) vs soxr VHQ vs
# libsamplerate SINC_BEST, on the conversions the Enhanced path actually performs (file rate -> 48 kHz).
import sys, os, subprocess, time, ctypes, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, 'pylib'))
import soxr
TMP = os.path.join(ROOT, 'out', 'src'); os.makedirs(TMP, exist_ok=True)
lsr = ctypes.CDLL('/opt/homebrew/lib/libsamplerate.dylib')
class SRC_DATA(ctypes.Structure):
    _fields_ = [('data_in', ctypes.POINTER(ctypes.c_float)), ('data_out', ctypes.POINTER(ctypes.c_float)),
                ('input_frames', ctypes.c_long), ('output_frames', ctypes.c_long),
                ('input_frames_used', ctypes.c_long), ('output_frames_gen', ctypes.c_long),
                ('end_of_input', ctypes.c_int), ('src_ratio', ctypes.c_double)]
def lsr_best(x, fi, fo):
    x = np.ascontiguousarray(x, dtype=np.float32); n_out = int(len(x) * fo / fi) + 1000
    y = np.zeros(n_out, dtype=np.float32)
    d = SRC_DATA(x.ctypes.data_as(ctypes.POINTER(ctypes.c_float)), y.ctypes.data_as(ctypes.POINTER(ctypes.c_float)),
                 len(x), n_out, 0, 0, 1, fo / fi)
    err = lsr.src_simple(ctypes.byref(d), 0, 1)
    assert err == 0, err
    return y[:d.output_frames_gen]
def avac(x, fi, fo, algo):
    pin = os.path.join(TMP, 'in.f32'); pout = os.path.join(TMP, 'out.f32')
    np.asarray(x, dtype=np.float32).tofile(pin)
    r = subprocess.run([os.path.join(ROOT, 'out', 'src_dump'), str(fi), str(fo), algo, 'max', pin, pout], capture_output=True, text=True)
    info = dict(kv.split('=') for kv in r.stderr.split())
    return np.fromfile(pout, dtype=np.float32), info
CONVS = {
    'AVAC max Normal (prod)': lambda x, fi, fo: avac(x, fi, fo, 'normal')[0],
    'AVAC max Mastering':     lambda x, fi, fo: avac(x, fi, fo, 'mastering')[0],
    'AVAC max MinimumPhase':  lambda x, fi, fo: avac(x, fi, fo, 'minphase')[0],
    'soxr VHQ':               lambda x, fi, fo: soxr.resample(np.asarray(x, np.float32), fi, fo, quality='VHQ'),
    'libsamplerate BEST':     lambda x, fi, fo: lsr_best(x, fi, fo),
}
N = 1 << 17
W = np.kaiser(N, 24.0); SW2 = np.sum(W * W)
def spectrum(y, fo):
    seg = y[16384:16384 + N].astype(np.float64)
    assert len(seg) == N, len(y)
    X = np.fft.rfft(seg * W)
    P = np.abs(X) ** 2
    return P, fo / N
def tone_amp(P, df, f, half=14):
    k = int(round(f / df)); lo, hi = max(k - half, 1), min(k + half + 1, len(P))
    return np.sqrt(4 * P[lo:hi].sum() / (N * SW2))
def worst_spur(P, df, exclude_f=None, half=14, min_f=20.0):
    P2 = P.copy(); P2[:int(min_f / df)] = 0
    if exclude_f is not None:
        k = int(round(exclude_f / df)); P2[max(k - 3 * half, 0):k + 3 * half + 1] = 0
    k = int(np.argmax(P2)); f = k * df
    return tone_amp(P2, df, f, half), f
def db(v): return 20 * np.log10(max(v, 1e-30))
def tone(f, fi, secs=4.0, amp=0.5):
    n = int(secs * fi); t = np.arange(n) / fi
    return (amp * np.sin(2 * np.pi * f * t)).astype(np.float32)
cases = [(44100, 48000), (88200, 48000), (96000, 48000), (192000, 48000)]
print('# Passband (dB re input) and worst in-band spur (dBc) per tone; stopband = worst alias of an out-of-band tone (dB re tone)')
for fi, fo in cases:
    print(f'\n== {fi} -> {fo} ==')
    for name, fn in CONVS.items():
        row = []
        for f in [1000, 10000, 18000, 20000, 21000, 22000]:
            if f >= min(fi, fo) / 2: continue
            y = fn(tone(f, fi), fi, fo); P, df = spectrum(y, fo)
            a = tone_amp(P, df, f); s, sf = worst_spur(P, df, exclude_f=f)
            row.append(f'{f/1000:g}k:{db(a/0.5):+.3f}dB/spur{db(s/a):.0f}@{sf/1000:.1f}k')
        stop = []
        if fi > fo:
            for f in [24500, 25000, 26000, 30000, 40000, 44000]:
                if f >= fi / 2: continue
                y = fn(tone(f, fi), fi, fo); P, df = spectrum(y, fo)
                s, sf = worst_spur(P, df)
                stop.append(f'{f/1000:g}k->{db(s/0.5):.0f}dB@{sf/1000:.1f}k')
        print(f'  {name:24s} ' + '  '.join(row))
        if stop: print(f'  {"":24s} stopband: ' + '  '.join(stop))
# CPU: 60 s mono, production pattern for AVAC (per channel)
print('\n# CPU cost, 60 s mono (seconds of CPU per 60 s of audio; production runs N channels on a background queue)')
for fi, fo in [(44100, 48000), (96000, 48000)]:
    x = (np.random.default_rng(1).standard_normal(int(60 * fi)) * 0.1).astype(np.float32)
    for algo in ['normal', 'mastering', 'minphase']:
        y, info = avac(x, fi, fo, algo)
        print(f'  {fi}->{fo} AVAC {algo:9s}: {float(info["cpu_seconds"]):.3f} s  (prime leading={info["primeLeading"]} trailing={info["primeTrailing"]})')
    t = time.perf_counter(); soxr.resample(x, fi, fo, quality='VHQ'); print(f'  {fi}->{fo} soxr VHQ      : {time.perf_counter()-t:.3f} s')
    t = time.perf_counter(); lsr_best(x, fi, fo); print(f'  {fi}->{fo} lsr BEST      : {time.perf_counter()-t:.3f} s')
