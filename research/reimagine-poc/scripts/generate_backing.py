#!/usr/bin/env python3
"""Stage-0: drive ACE-Step 1.5 'Complete' mode (vocal -> accompaniment) via the REST API.

Submits a `complete` task (source audio = isolated/restored vocal, caption = style), polls
/query_result, and downloads the generated backing take(s). Run with several style prompts.

Usage:
  generate_backing.py --vocal out/vocals_restored_44k.wav \
      --prompt "traditional Sri Lankan folk, sitar, tabla, harmonium, gentle percussion, minor key" \
      --tag folk --steps 60 --duration 45 --batch 2
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
import time
from pathlib import Path

import requests

API = "http://localhost:8001"


def submit(vocal: Path, prompt: str, steps: int, duration: float, batch: int) -> str:
    # IMPORTANT: send JSON (not multipart). Multipart coerces every field to a string, and the
    # server does an int comparison on numeric fields -> 500 "'<' not supported between str and int".
    # The server is local, so reference the vocal by ABSOLUTE PATH (src_audio_path) instead of upload.
    payload = {
        "task_type": "complete",            # add accompaniment to the source (vocal)
        "src_audio_path": str(vocal.resolve()),
        "prompt": prompt,                    # style caption
        "audio_duration": duration,          # typed float
        "thinking": True,                    # base model uses the 5Hz LM to plan
        "inference_steps": steps,            # typed int; base model: 32-64 recommended
        "guidance_scale": 7.0,               # base-model only
        "audio_format": "wav",
        "batch_size": batch,                 # typed int
    }
    # /release_task blocks until generation finishes (synchronous); long timeout for full-length takes.
    r = requests.post(f"{API}/release_task", json=payload, timeout=3600)
    r.raise_for_status()
    body = r.json()
    tid = body.get("data", {}).get("task_id")
    if not tid:
        sys.exit(f"no task_id in response: {body}")
    print(f"  submitted task_id={tid}  (status={body['data'].get('status')})")
    return tid


def poll(task_id: str, timeout_s: int = 3600) -> list[str]:
    t0 = time.time()
    while time.time() - t0 < timeout_s:
        r = requests.post(f"{API}/query_result", json={"task_id_list": [task_id]}, timeout=60)
        r.raise_for_status()
        entry = r.json()["data"][0]
        status = entry["status"]
        if status == 1:
            results = json.loads(entry["result"])
            return [it["file"] for it in results if it.get("file")]
        if status == 2:
            sys.exit(f"  generation FAILED: {entry}")
        print(f"  ...{int(time.time()-t0)}s status={status}", flush=True)
        time.sleep(5)
    sys.exit("  timed out waiting for generation")


def collect(src_file: str, dest: Path) -> None:
    # poll() returns the server's LOCAL absolute output path; copy it (no HTTP fetch needed).
    src = Path(src_file)
    if not src.exists():
        sys.exit(f"  output file missing: {src}")
    shutil.copy2(src, dest)
    print(f"  wrote {dest}  ({dest.stat().st_size // 1024} KB)")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--vocal", required=True, type=Path)
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--tag", required=True, help="short label for output filenames")
    ap.add_argument("--steps", type=int, default=60)
    ap.add_argument("--duration", type=float, default=45.0)
    ap.add_argument("--batch", type=int, default=2)
    ap.add_argument("--outdir", type=Path, default=Path("out/backing"))
    args = ap.parse_args()
    args.outdir.mkdir(parents=True, exist_ok=True)

    t_start = time.time()
    print(f"[{args.tag}] prompt: {args.prompt}")
    tid = submit(args.vocal, args.prompt, args.steps, args.duration, args.batch)
    files = poll(tid)
    for i, furl in enumerate(files):
        collect(furl, args.outdir / f"backing_{args.tag}_{i}.wav")
    print(f"[{args.tag}] done in {time.time()-t_start:.0f}s — {len(files)} take(s)")


if __name__ == "__main__":
    main()
