"""Summarise aes_eq_probe.json: per-clip deltas vs flat, controls, and per-window sign consistency."""

import json
import sys

import numpy as np

AXES = ["PQ", "PC", "CE", "CU"]
r = json.load(open(sys.argv[1]))
print("device", r["device"], "load_s %.2f" % r["load_s"])
clips = list(r["clips"])
names = list(r["clips"][clips[0]]["variants"])

for c in clips:
    cl = r["clips"][c]
    flat = cl["variants"]["flat"]["mean"]
    print(f"\n## {c}  fs={cl['fs']}  ref {cl['ref_lufs']:.1f} LUFS  flat: " +
          " ".join(f"{a} {flat[a]:.2f}" for a in AXES))
    print("variant | match gain dB | peak dBFS | " + " | ".join(f"d{a}" for a in AXES) + " | PQ windows (d)")
    for n in names:
        v = cl["variants"][n]
        d = {a: v["mean"][a] - flat[a] for a in AXES}
        wins = [w["PQ"] - fw["PQ"] for w, fw in zip(v["windows"], cl["variants"]["flat"]["windows"])]
        print(f"{n} | {v['match_gain_db']:+.2f} | {v['peak_dbfs']:+.1f} | " +
              " | ".join(f"{d[a]:+.3f}" for a in AXES) + " | " + ", ".join(f"{w:+.2f}" for w in wins))
    print("controls (delta vs flat):")
    for k, v in cl["controls"].items():
        print(f"  {k}: " + " ".join(f"{a} {v[a] - flat[a]:+.3f}" for a in AXES))
    fw = cl["variants"]["flat"]["windows"]
    print("  flat window-to-window SD: " + " ".join(f"{a} {np.std([w[a] for w in fw]):.3f}" for a in AXES))

# Pooled: mean delta across clips, and in how many of the 9 (clip, window) pairs the PQ delta keeps its sign.
print("\n## pooled over clips (mean dPQ, dCE; sign agreement of dPQ over 9 windows)")
for n in names[1:]:
    dpq, dce, signs = [], [], []
    for c in clips:
        cl = r["clips"][c]
        flat = cl["variants"]["flat"]
        dpq.append(cl["variants"][n]["mean"]["PQ"] - flat["mean"]["PQ"])
        dce.append(cl["variants"][n]["mean"]["CE"] - flat["mean"]["CE"])
        signs += [np.sign(w["PQ"] - f["PQ"]) for w, f in zip(cl["variants"][n]["windows"], flat["windows"])]
    s = np.array(signs)
    agree = max((s > 0).sum(), (s < 0).sum())
    print(f"{n}: dPQ " + " ".join(f"{x:+.2f}" for x in dpq) + f"  mean {np.mean(dpq):+.2f} | dCE mean {np.mean(dce):+.2f} | sign agree {agree}/9")
noise = []
for c in clips:
    cl = r["clips"][c]
    flat = cl["variants"]["flat"]["mean"]
    for k, v in cl["controls"].items():
        if k.startswith("shift"):
            noise.append(abs(v["PQ"] - flat["PQ"]))
print("alignment-shift |dPQ| max %.3f mean %.3f" % (max(noise), np.mean(noise)))
