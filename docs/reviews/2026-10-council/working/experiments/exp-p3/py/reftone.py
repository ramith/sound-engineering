# Reference tone (AudioEngineBridge+ReferenceTone.swift:37-59): Float32 angle = phaseInc * Float(i),
# no wrap, vForce.sin (single precision), gain 0.3. Oracle: double-precision sin(2*pi*f*i/fs) * 0.3.
import numpy as np
fs, f, n = np.float32(48000.0), np.float32(1000.0), 240000
inc = np.float32(2.0) * np.float32(np.pi) * f / fs
i = np.arange(n, dtype=np.float32)
ang = (inc * i).astype(np.float32)
y = (np.sin(ang.astype(np.float32)).astype(np.float32) * np.float32(0.3)).astype(np.float32)
ideal = 0.3 * np.sin(2 * np.pi * 1000.0 * np.arange(n) / 48000.0)
err = y.astype(np.float64) - ideal
for lo, hi in [(0, 4800), (n - 4800, n)]:
    e = err[lo:hi]; s = ideal[lo:hi]
    print(f"frames {lo}-{hi}: error rms {20*np.log10(np.sqrt(np.mean(e**2))/np.sqrt(np.mean(s**2))):.1f} dB re tone, peak {20*np.log10(np.max(np.abs(e))/0.3):.1f} dB")
# with a wrapped double accumulator (ToneSource.cpp's method) for comparison
ph = 0.0; out = np.empty(n); inc_d = 2*np.pi*1000.0/48000.0
for k in range(n):
    out[k] = 0.3*np.sin(ph); ph += inc_d
    if ph >= 2*np.pi: ph -= 2*np.pi
e2 = out - ideal
print(f"ToneSource-style double accumulator: error rms over all {20*np.log10(np.sqrt(np.mean(e2**2))/(0.3/np.sqrt(2))):.1f} dB re tone")
