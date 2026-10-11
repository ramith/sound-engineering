"""Does Essentia's timbre (bright/dark) head follow a treble shelf? usage: python -I effnet_timbre_probe.py <models> <wav:start> ..."""

import os
import sys

import numpy as np
import scipy.signal as ss

import essentia
import essentia.standard as es

essentia.log.infoActive = False
essentia.log.warningActive = False


def high_shelf(fs, f0, gain_db):
    a_lin = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * f0 / fs
    cw, sw = np.cos(w0), np.sin(w0)
    alpha = sw / 2 * np.sqrt(2)
    sq = 2 * np.sqrt(a_lin) * alpha
    b = [a_lin * ((a_lin + 1) + (a_lin - 1) * cw + sq), -2 * a_lin * ((a_lin - 1) + (a_lin + 1) * cw),
         a_lin * ((a_lin + 1) + (a_lin - 1) * cw - sq)]
    a = [(a_lin + 1) - (a_lin - 1) * cw + sq, 2 * ((a_lin - 1) - (a_lin + 1) * cw), (a_lin + 1) - (a_lin - 1) * cw - sq]
    return np.array(b) / a[0], np.array(a) / a[0]


def main():
    models = sys.argv[1]
    embed = es.TensorflowPredictEffnetDiscogs(graphFilename=os.path.join(models, "discogs-effnet-bs64-1.pb"),
                                              output="PartitionedCall:1")
    timbre = es.TensorflowPredict2D(graphFilename=os.path.join(models, "timbre-discogs-effnet-1.pb"), output="model/Softmax")
    for arg in sys.argv[2:]:
        path, start = arg.rsplit(":", 1)
        audio = es.MonoLoader(filename=path, sampleRate=16000)()
        x = audio[int(float(start) * 16000): int((float(start) + 30) * 16000)].astype(np.float64)
        row = []
        for g in (-12, -6, 0, 6, 12):
            if g:
                b, a = high_shelf(16000, 4000, g)  # 4 kHz at the 16 kHz model rate (6 kHz would sit near Nyquist)
                y = ss.lfilter(b, a, x)
            else:
                y = x
            y = (y * np.sqrt(np.mean(x ** 2) / np.mean(y ** 2))).astype(np.float32)  # RMS-matched
            p = timbre(embed(y)).mean(axis=0)
            row.append(f"{g:+d} dB: bright {p[0]:.2f}")
        print(os.path.basename(path), " | ".join(row))


if __name__ == "__main__":
    main()
