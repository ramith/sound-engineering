"""Item 3: refinement-pass count on a Rämö-style command set at 44.1-192 kHz, plus the response above 20 kHz."""
import numpy as np, json, geq2 as G
rng = np.random.default_rng(2020)
sets = {"presets": list(G.PRESETS.values()), "tone (100)": G.tone_set(rng), "smooth (200)": G.smooth_set(rng),
        "ramo binary+integer (1000)": G.ramo_set(rng)}
hard = G.hard_set(); sets["hard patterns"] = list(hard.values())
P = 8
res = {}
for fs in G.SAMPLE_RATES:
    for name, cmds in sets.items():
        errs = np.zeros((len(cmds), P + 1))
        for i, t in enumerate(cmds):
            for p, g in enumerate(G.solve_passes(t, fs, P)):
                errs[i, p] = G.centre_err(t, g, fs)
        res[(fs, name)] = errs
    print(f"done {fs}", flush=True)
lines = ["Max |played - target| at the 31 centres (dB), worst over the set; columns = refinement passes after the first solve"]
lines.append(f"{'set':28s} {'fs':>6s} " + " ".join(f"{p:>6d}" for p in range(P + 1)))
for name in sets:
    for fs in G.SAMPLE_RATES:
        e = res[(fs, name)]
        lines.append(f"{name:28s} {fs/1000:6.1f} " + " ".join(f"{e[:, p].max():6.3f}" for p in range(P + 1)))
lines.append("\nWorst over all six rates, per set (passes 2 / 3 / 4 / 6 / 8):")
for name in sets:
    w = [max(res[(fs, name)][:, p].max() for fs in G.SAMPLE_RATES) for p in (2, 3, 4, 6, 8)]
    p99 = [np.percentile(np.concatenate([res[(fs, name)][:, p] for fs in G.SAMPLE_RATES]), 99) for p in (2, 3, 4, 6, 8)]
    lines.append(f"  {name:28s} max " + " / ".join(f"{x:.3f}" for x in w) + "   p99 " + " / ".join(f"{x:.3f}" for x in p99))
lines.append("\nHard patterns, per pattern, worst over rates (passes 2 / 3 / 8):")
for j, hn in enumerate(hard):
    w = [max(res[(fs, "hard patterns")][j, p] for fs in G.SAMPLE_RATES) for p in (2, 3, 8)]
    lines.append(f"  {hn:32s} " + " / ".join(f"{x:.3f}" for x in w))
# ultrasonic: response above band 31 vs the band-31 target
lines.append("\nResponse above 20 kHz (max over 20.2 kHz .. 0.999 Nyquist), dB, passes = 5:")
ucases = {"+12 @ 20 kHz": hard["single+12@30"], "edge -12/+12 (16k/20k)": hard["edge -12/+12 (16k/20k)"],
          "all +12": hard["all+12"], "alternating": hard["alternating"],
          "Tone Air +12": G.apply_tone(np.zeros(G.NB), [0, 0, 0, 0, 12])}
lines.append(f"  {'curve':26s} " + " ".join(f"{fs/1000:>8.1f}k" for fs in G.SAMPLE_RATES) + "   (audible-band peak @44.1k)")
for cn, t in ucases.items():
    row = []
    for fs in G.SAMPLE_RATES:
        g = G.design(t, fs, 5); f = np.geomspace(20200, 0.999 * fs / 2, 2000)
        row.append(G.response_db(g, f, fs, G.C, "bilinear").max())
    g = G.design(t, 44100., 3); pk = G.response_db(g, np.geomspace(20, 20000, 4000), 44100., G.C, "bilinear").max()
    lines.append(f"  {cn:26s} " + " ".join(f"{x:+9.2f}" for x in row) + f"   {pk:+.2f}")
txt = "\n".join(lines); print(txt); open("results/s1_solver_passes.txt", "w").write(txt + "\n")
