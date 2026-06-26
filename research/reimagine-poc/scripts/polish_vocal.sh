#!/usr/bin/env bash
# Tasteful "remaster" polish for an isolated+restored vocal — known, low-risk tech only:
#   highpass  : remove subsonic rumble / separation bleed below the voice
#   deesser   : tame sibilance that isolation+restoration tends to exaggerate
#   air shelf : gentle high-shelf for presence/"air" on an old, dull recording
#               (conservative EQ, NOT neural bandwidth-extension — avoids the metallic artifact)
#   loudnorm  : EBU R128 loudness normalize so it's comfortable to listen to standalone
# Usage: polish_vocal.sh <in.wav> <out.wav> [air_gain_dB]
set -euo pipefail
cd "$(dirname "$0")/.."
IN="$1"; OUT="$2"; AIR="${3:-2.5}"
ffmpeg -hide_banner -v error -y -i "$IN" -af "\
  highpass=f=75,\
  deesser=i=0.30:m=0.5:f=0.18,\
  equalizer=f=9500:t=h:w=8000:g=${AIR},\
  loudnorm=I=-16:TP=-1.5:LRA=11" \
  -ar 44100 -ac 2 "$OUT"
echo "  polished -> $OUT (air +${AIR}dB)"
