#!/usr/bin/env python3
"""Tempo-match + beat-align a generated backing to a vocal, then mix (turbo Level-2 workflow).

Since turbo generates 'blind' (no vocal conditioning), we make the backing fit the produced
vocal's steady grid:
  1. stretch backing to the vocal's tempo (rubberband, pitch-preserving — good for ~25% stretches)
  2. beat-align via onset-envelope cross-correlation (find the lag that lines up the grooves)
  3. mix: vocal -16 LUFS over backing -20 LUFS + limiter (same as rough_mix)

Usage: align_mix.py --vocal V.wav --backing B.wav --target-bpm 123 --out OUT.wav
"""
from __future__ import annotations
import argparse, shutil, subprocess, tempfile, os
import numpy as np, soundfile as sf, librosa

SR = 44100
ENV_SR = 22050
HOP = 512


def detected_tempo(mono, target):
    t, _ = librosa.beat.beat_track(y=mono, sr=ENV_SR)
    t = float(np.atleast_1d(t)[0])
    # resolve half/double-time ambiguity: pick interpretation closest (in octaves) to target
    return min([t, t * 2, t / 2], key=lambda c: abs(np.log2(c / target)))


def stretch_to(infile, ratio, outfile):
    if shutil.which("rubberband"):
        subprocess.run(["rubberband", "--tempo", f"{ratio:.6f}", "-q", infile, outfile],
                       check=True, capture_output=True)
    else:  # fallback: phase vocoder (lower quality for big stretches)
        y, _ = librosa.load(infile, sr=SR, mono=False)
        y = np.atleast_2d(y)
        ys = np.stack([librosa.effects.time_stretch(y[c], rate=ratio) for c in range(y.shape[0])])
        sf.write(outfile, ys.T, SR)


def best_lag_seconds(voc_mono, bk_mono, max_lag_s=1.0):
    ev = librosa.onset.onset_strength(y=voc_mono, sr=ENV_SR, hop_length=HOP)
    eb = librosa.onset.onset_strength(y=bk_mono, sr=ENV_SR, hop_length=HOP)
    n = min(len(ev), len(eb)); ev = ev[:n] - ev[:n].mean(); eb = eb[:n] - eb[:n].mean()
    full = np.correlate(ev, eb, "full")
    lags = np.arange(-len(eb) + 1, len(ev))
    fps = ENV_SR / HOP
    win = int(max_lag_s * fps)
    mask = np.abs(lags) <= win
    peak = lags[mask][np.argmax(full[mask])]
    return peak / fps  # >0 => delay backing; <0 => advance backing


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vocal", required=True)
    ap.add_argument("--backing", required=True)
    ap.add_argument("--target-bpm", type=float, required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    tmp = tempfile.mkdtemp()

    # 1) tempo match
    bk_mono0, _ = librosa.load(a.backing, sr=ENV_SR, mono=True)
    src_bpm = detected_tempo(bk_mono0, a.target_bpm)
    ratio = a.target_bpm / src_bpm
    stretched = os.path.join(tmp, "stretched.wav")
    stretch_to(a.backing, ratio, stretched)
    print(f"  tempo: {src_bpm:.1f} -> {a.target_bpm:.0f} BPM (x{ratio:.3f})")

    # 2) beat-align via onset xcorr
    voc, _ = librosa.load(a.vocal, sr=SR, mono=False); voc = np.atleast_2d(voc)
    bk, _ = librosa.load(stretched, sr=SR, mono=False); bk = np.atleast_2d(bk)
    if voc.shape[0] == 1: voc = np.vstack([voc, voc])
    if bk.shape[0] == 1: bk = np.vstack([bk, bk])
    vm = librosa.resample(voc.mean(0), orig_sr=SR, target_sr=ENV_SR)
    bm = librosa.resample(bk.mean(0), orig_sr=SR, target_sr=ENV_SR)
    lag_s = best_lag_seconds(vm, bm)
    shift = int(round(lag_s * SR))
    if shift > 0:      # delay backing
        bk = np.pad(bk, ((0, 0), (shift, 0)))
    elif shift < 0:    # advance backing
        bk = bk[:, -shift:]
    print(f"  beat align: shift backing {lag_s*1000:+.0f} ms")

    # length-match to vocal
    nlen = voc.shape[1]
    bk = bk[:, :nlen] if bk.shape[1] >= nlen else np.pad(bk, ((0, 0), (0, nlen - bk.shape[1])))
    aligned = os.path.join(tmp, "aligned.wav")
    sf.write(aligned, bk.T, SR)

    # 3) mix (loudnorm + limiter)
    subprocess.run([
        "ffmpeg", "-hide_banner", "-v", "error", "-y", "-i", a.vocal, "-i", aligned,
        "-filter_complex",
        "[0:a]aformat=sample_rates=44100:channel_layouts=stereo,loudnorm=I=-16:TP=-1.5:LRA=11[v];"
        "[1:a]aformat=sample_rates=44100:channel_layouts=stereo,loudnorm=I=-20:TP=-1.5:LRA=11[b];"
        "[v][b]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.97[m]",
        "-map", "[m]", "-ar", "44100", "-ac", "2", a.out,
    ], check=True)
    print(f"  -> {a.out}")


if __name__ == "__main__":
    main()
