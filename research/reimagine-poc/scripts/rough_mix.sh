#!/usr/bin/env bash
# Stage-0 rough mix: level-match the restored vocal over each generated backing — just enough to JUDGE
# (no DTW alignment, no mastering). Vocal sits ~4 dB hotter than the backing so it stays intelligible.
#   vocal  -> -16 LUFS   (foreground)
#   backing-> -20 LUFS   (bed)
# Sum (normalize=0 so levels are honoured), then a gentle limiter as a clip guard. 44.1k stereo out.
set -euo pipefail
cd "$(dirname "$0")/.."

VOCAL=out/vocals_restored_44k.wav
OUTDIR=out
mkdir -p "$OUTDIR"

shopt -s nullglob
takes=(out/backing/backing_*.wav)
if [ ${#takes[@]} -eq 0 ]; then echo "no backings in out/backing/"; exit 1; fi

for b in "${takes[@]}"; do
  tag="$(basename "$b" .wav | sed 's/^backing_//')"
  out="$OUTDIR/stage0_mix_${tag}.wav"
  echo "[mix] $tag  <-  vocal + $(basename "$b")"
  ffmpeg -y -v error \
    -i "$VOCAL" -i "$b" \
    -filter_complex "\
      [0:a]aformat=sample_rates=44100:channel_layouts=stereo,loudnorm=I=-16:TP=-1.5:LRA=11[v];\
      [1:a]aformat=sample_rates=44100:channel_layouts=stereo,loudnorm=I=-20:TP=-1.5:LRA=11[bk];\
      [v][bk]amix=inputs=2:duration=longest:normalize=0,alimiter=limit=0.97[mix]" \
    -map "[mix]" -ar 44100 -ac 2 "$out"
  echo "       -> $out"
done
echo "[mix] done. Listen: $(ls "$OUTDIR"/stage0_mix_*.wav 2>/dev/null | tr '\n' ' ')"
