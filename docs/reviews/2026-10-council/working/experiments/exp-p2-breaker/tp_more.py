import numpy as np, sys
from tp_multi import dac_tp
from tp_oracle import true_peak
for tag, ceil in (("c891",-1.0022),("c0988",-0.1)):
    for name in ("clipped_pink_x4","clipped_white_x3","tanh_pink_drive8","clipped_hp_noise"):
        d = np.fromfile(f"lim_{tag}_{name}.f32", dtype=np.float32).reshape(-1,2)
        ideal = max(true_peak(d[:,0])[0], true_peak(d[:,1])[0]); dac = max(dac_tp(d[:,0]), dac_tp(d[:,1]))
        # count 10-ms windows with ideal TP over ceiling
        x = d[:,0].astype(np.float64)
        print(f"{tag} {name:18s} idealTP={ideal:7.3f} dacTP={dac:7.3f} ceiling={ceil}")
