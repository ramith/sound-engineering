"""Discogs-EffNet read-ahead benchmark: Essentia-TensorFlow (reference) and ONNX Runtime (CPU, CoreML EP).

usage: python -I effnet_bench.py <models_dir> <wav> [<wav> ...]
Prints wall time per stage for each file, and the top genre / mood-theme / timbre outputs.
"""

import json
import os
import sys
import time

import numpy as np

import essentia
import essentia.standard as es

essentia.log.infoActive = False
essentia.log.warningActive = False


def labels(models, name):
    with open(os.path.join(models, name + ".json")) as f:
        return json.load(f)["classes"]


def top(probs, classes, k=3):
    mean = probs.mean(axis=0)
    idx = np.argsort(mean)[::-1][:k]
    return ", ".join(f"{classes[i]} {mean[i]:.2f}" for i in idx)


def mel_patches(audio16k):
    """The EffNet input: 96-band mel frames (512/256 at 16 kHz), cut into 128-frame patches, hop 62."""
    frames = []
    feat = es.TensorflowInputMusiCNN()
    for frame in es.FrameGenerator(audio16k, frameSize=512, hopSize=256, startFromZero=True):
        frames.append(feat(frame))
    mel = np.array(frames, dtype=np.float32)
    patches = [mel[i:i + 128] for i in range(0, len(mel) - 128 + 1, 62)]
    return np.stack(patches)


def main():
    models = sys.argv[1]
    effnet_pb = os.path.join(models, "discogs-effnet-bs64-1.pb")
    t = time.perf_counter()
    embed = es.TensorflowPredictEffnetDiscogs(graphFilename=effnet_pb, output="PartitionedCall:1")
    heads = {
        "genre": es.TensorflowPredict2D(graphFilename=os.path.join(models, "genre_discogs400-discogs-effnet-1.pb"),
                                        input="serving_default_model_Placeholder", output="PartitionedCall:0"),
        "moodtheme": es.TensorflowPredict2D(graphFilename=os.path.join(models, "mtg_jamendo_moodtheme-discogs-effnet-1.pb")),
        "timbre": es.TensorflowPredict2D(graphFilename=os.path.join(models, "timbre-discogs-effnet-1.pb"), output="model/Softmax"),
        "acoustic": es.TensorflowPredict2D(graphFilename=os.path.join(models, "mood_acoustic-discogs-effnet-1.pb"), output="model/Softmax"),
    }
    print(f"model load {time.perf_counter() - t:.2f} s")
    names = {"genre": labels(models, "genre_discogs400-discogs-effnet-1"),
             "moodtheme": labels(models, "mtg_jamendo_moodtheme-discogs-effnet-1"),
             "timbre": labels(models, "timbre-discogs-effnet-1"),
             "acoustic": labels(models, "mood_acoustic-discogs-effnet-1")}

    import onnxruntime as ort
    onnx_path = os.path.join(models, "discogs-effnet-bsdynamic-1.onnx")
    sessions = {p: ort.InferenceSession(onnx_path, providers=[p, "CPUExecutionProvider"])
                for p in ("CPUExecutionProvider", "CoreMLExecutionProvider")}

    for wav in sys.argv[2:]:
        t0 = time.perf_counter()
        audio = es.MonoLoader(filename=wav, sampleRate=16000, resampleQuality=4)()
        t_load = time.perf_counter() - t0
        dur = len(audio) / 16000

        t1 = time.perf_counter()
        emb = embed(audio)
        t_embed = time.perf_counter() - t1

        t2 = time.perf_counter()
        outs = {k: h(emb) for k, h in heads.items()}
        t_heads = time.perf_counter() - t2

        t3 = time.perf_counter()
        patches = mel_patches(audio)
        t_mel = time.perf_counter() - t3
        onnx_t = {}
        for p, s in sessions.items():
            s.run(None, {"melspectrogram": patches[:4]})  # warm-up
            t4 = time.perf_counter()
            act, onnx_emb = s.run(None, {"melspectrogram": patches})
            onnx_t[p] = time.perf_counter() - t4
        diff = float(np.max(np.abs(onnx_emb - emb[: len(onnx_emb)]))) if len(onnx_emb) == len(emb) else float("nan")

        print(f"\n{os.path.basename(wav)}: {dur:.1f} s audio, {emb.shape[0]} patches x {emb.shape[1]}-d embedding")
        print(f"  decode+resample {t_load:.2f} s | TF embed {t_embed:.2f} s | 4 heads {t_heads:.3f} s")
        print(f"  ONNX: mel {t_mel:.2f} s | " + " | ".join(f"{p.replace('ExecutionProvider', '')} {v:.2f} s" for p, v in onnx_t.items())
              + f" | max |emb diff| TF vs ONNX {diff:.2e}")
        for k in outs:
            print(f"  {k}: {top(outs[k], names[k])}")


if __name__ == "__main__":
    main()
