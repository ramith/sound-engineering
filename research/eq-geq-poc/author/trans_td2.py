"""Item 2 follow-up: can the adversarial jagged transitions be tamed? S2 with (a) tau 10 ms direct, (b) tau 30 ms
direct, (c) direct path but routed through Off (flat, gain 0) when the Realizer's path check predicts a swell:
A -> Off at T0, Off -> B at T0 + 40 ms. Same overshoot metrics as trans_td.py (local [Hz] / peak, dB)."""
import numpy as np, trans_td as T, geq2 as G
from concurrent.futures import ThreadPoolExecutor
from scipy.signal import hilbert
fs = T.fs; N = T.N; n0 = int(T.T0 * fs)
def ovs(events, probes, mode=1, tau=0.010):
    T.TAU = tau
    def one(p):
        env = np.abs(hilbert(T.run(events, mode, p)))
        a = np.median(env[n0 - int(0.08 * fs):n0 - int(0.01 * fs)]); b = np.median(env[-int(0.1 * fs):-int(0.03 * fs)])
        return env[n0:n0 + int(0.3 * fs)].max(), a, b
    with ThreadPoolExecutor(10) as ex: r = np.array(list(ex.map(one, probes)))
    T.TAU = 0.010
    loc = 20 * np.log10(r[:, 0] / np.maximum(r[:, 1], r[:, 2]))
    return loc.max(), probes[int(np.argmax(loc))], 20 * np.log10(r[:, 0].max() / np.maximum(r[:, 1], r[:, 2]).max())
if __name__ == "__main__":
    flat = np.zeros(G.NB); h = G.hard_set()
    wp = np.load("../../review/breaker/worst_pair.npy"); a1 = np.load("results/adv_pair_S1.npy"); a2 = np.load("results/adv_pair_S2.npy")
    pairs = {"breaker worst pair A->B": (wp[0], wp[1]), "breaker worst pair B->A": (wp[1], wp[0]), "S1-adversarial": (a1[0], a1[1]),
             "S2-adversarial": (a2[0], a2[1]), "alt+ -> alt-": (h["alternating"], -h["alternating"])}
    P = np.geomspace(25, 18000, 48)
    lines = [__doc__, f"{'pair':26s} {'S2 tau10 direct':>24s} {'S2 tau30 direct':>24s} {'S2 tau10 via Off':>24s} {'S1 tau10 via Off':>24s}"]
    for nm, (a, b) in pairs.items():
        A, B, O = T.ep(a), T.ep(b), T.ep(flat)
        r = [ovs([(0.0, A), (T.T0, B)], P), ovs([(0.0, A), (T.T0, B)], P, tau=0.030),
             ovs([(0.0, A), (T.T0, O), (T.T0 + 0.04, B)], P), ovs([(0.0, A), (T.T0, O), (T.T0 + 0.04, B)], P, mode=0)]
        lines.append(f"{nm:26s} " + " ".join(f"{x[0]:+6.2f} [{x[1]:5.0f}] / {x[2]:+5.2f}" for x in r)); print(lines[-1], flush=True)
    open("results/s2d_transition_td_mitigation.txt", "w").write("\n".join(lines) + "\n")
