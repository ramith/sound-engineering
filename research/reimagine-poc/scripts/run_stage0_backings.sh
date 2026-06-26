#!/usr/bin/env bash
# Stage-0: generate 3 style-variant backings from the restored Sinhala vocal (Complete mode, base DiT).
# Server processes one task at a time, so these run sequentially. ~7-12 min each at 40 steps / 45s.
set -euo pipefail
cd "$(dirname "$0")/.."

PY=vendor/ACE-Step-1.5/.venv/bin/python
VOCAL=out/vocals_restored_44k.wav
STEPS=40
DUR=45

run () { # tag, prompt
  echo "=================================================================="
  echo "[$(date +%H:%M:%S)] generating: $1"
  "$PY" scripts/generate_backing.py --vocal "$VOCAL" --tag "$1" --prompt "$2" \
    --steps "$STEPS" --duration "$DUR" --batch 1 --outdir out/backing
}

run folk     "traditional Sri Lankan folk, sitar, tabla, harmonium, dholak, gentle percussion, minor scale, warm"
run acoustic "acoustic folk ballad, nylon guitar, soft hand percussion, warm strings, intimate, organic"
run modern   "modern cinematic folk-pop, live drums, electric bass, tasteful synth pads, lush, polished"

echo "=================================================================="
echo "[$(date +%H:%M:%S)] ALL DONE — takes in out/backing/"
ls -la out/backing/ 2>/dev/null
