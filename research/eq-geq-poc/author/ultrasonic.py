"""Response above 20 kHz vs the gain at band 31 (breaker m2), 5 refinement passes."""
import numpy as np, geq2 as G
h = G.hard_set()
cases = {"+12 @ 20 kHz": h["single+12@30"], "+6 @ 20 kHz": h["single+12@30"] / 2,
         "edge -12/+12 (16k/20k)": h["edge -12/+12 (16k/20k)"], "alternating": h["alternating"],
         "all +12": h["all+12"], "Tone Air +12": G.apply_tone(np.zeros(G.NB), [0, 0, 0, 0, 12])}
probe = [21000., 22000., 25000., 30000., 40000.]
lines = ["Response (dB) above 20 kHz; '-' = above Nyquist. Last column: in-band (20 Hz-20 kHz) peak."]
for fs in [44100., 48000., 96000., 192000.]:
    lines.append(f"fs {fs/1000:.1f}k   " + " ".join(f"{p/1000:>6.0f}k" for p in probe) + "   max(20.2k..Nyq)  in-band peak")
    for cn, t in cases.items():
        g = G.design(t, fs, 5)
        vals = [G.response_db(g, [p], fs, G.C, "bilinear")[0] if p < 0.4999 * fs else np.nan for p in probe]
        f = np.geomspace(20200, 0.999 * fs / 2, 3000); mx = G.response_db(g, f, fs, G.C, "bilinear").max()
        pk = G.response_db(g, np.geomspace(20, 20000, 4000), fs, G.C, "bilinear").max()
        lines.append(f"  {cn:24s}" + " ".join("     -" if np.isnan(v) else f"{v:+7.2f}" for v in vals) + f"   {mx:+7.2f}        {pk:+7.2f}")
txt = "\n".join(lines); print(txt); open("results/s1b_ultrasonic.txt", "w").write(txt + "\n")
