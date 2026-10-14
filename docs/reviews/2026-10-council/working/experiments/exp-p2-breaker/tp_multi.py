import numpy as np, sys, ctypes, os
from scipy import signal
from tp_oracle import true_peak
fs=48000
# DAC-like reconstruction: x16 polyphase, linear-phase Kaiser FIR, passband 0.4535 fs, stop 0.5465 fs (typical half-band "sharp" DAC filter)
up=16
numtaps = 16*64+1
h = signal.firwin2(numtaps, [0, 0.4535/up*2, 0.5465/up*2, 1], [1,1,0,0], window=('kaiser', 10)) * up
def dac_tp(x):
    y = signal.upfirdn(h, x.astype(np.float64), up)
    d = (numtaps-1)//2
    y = y[d: d+len(x)*up]
    return 20*np.log10(np.max(np.abs(y[2000*up:-2000*up]))+1e-30)
if __name__ == "__main__":
  for tag, ceil in (("c891",-1.0022),("c0988",-0.1)):
      for name in ("clipped_hp_noise","step_+12dB_19k","pink_+6dBFS_hot","sine1000_+0dBFS","step_+24dB_1k"):
          d = np.fromfile(f"lim_{tag}_{name}.f32", dtype=np.float32).reshape(-1,2)
          ideal = max(true_peak(d[:,0])[0], true_peak(d[:,1])[0])
          dac = max(dac_tp(d[:,0]), dac_tp(d[:,1]))
          sp = 20*np.log10(np.max(np.abs(d)))
          # fraction of 100 ms windows whose ideal TP exceeds the ceiling
          print(f"{tag} {name:20s} sample_pk={sp:7.3f} idealTP={ideal:7.3f} dacTP={dac:7.3f} ceiling={ceil}")
