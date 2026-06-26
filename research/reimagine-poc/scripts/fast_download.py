#!/usr/bin/env python3
"""Fast, robust model download via aria2c (16 connections/file) — defeats HF's per-connection throttle.

Downloads exactly the minimal set ACE-Step needs for Complete mode on a 24 GB Mac:
  - acestep-v15-base   (base DiT — Complete mode requires base, not turbo)
  - acestep-5Hz-lm-0.6B (0.6B LM — the 1.7B OOMs on 24 GB)
  - core from the main repo: vae/ + Qwen3-Embedding-0.6B/  (skips turbo + 1.7B → saves ~8 GB)
into vendor/ACE-Step-1.5/checkpoints/<...> mirroring the layout acestep-download produces.
"""
import os
import subprocess
from pathlib import Path

from huggingface_hub import HfApi

TOKEN = Path(os.path.expanduser("~/.cache/huggingface/token")).read_text().strip()
CKPT = Path("vendor/ACE-Step-1.5/checkpoints").resolve()
api = HfApi(token=TOKEN)

# (repo, dest_subdir_under_checkpoints, keep(path)->bool)
JOBS = [
    ("ACE-Step/acestep-5Hz-lm-0.6B", "acestep-5Hz-lm-0.6B", lambda p: True),
    ("ACE-Step/acestep-v15-base", "acestep-v15-base", lambda p: True),
    # main repo: only the core (vae + text embedder) + tiny top-level files; skip turbo + 1.7B
    ("ACE-Step/Ace-Step1.5", "", lambda p: p.startswith(("vae/", "Qwen3-Embedding-0.6B/")) or "/" not in p
        and not p.startswith(("acestep-v15-turbo", "acestep-5Hz-lm-1.7B"))),
]

lines = []
for repo, dest, keep in JOBS:
    for f in api.list_repo_files(repo):
        if not keep(f):
            continue
        url = f"https://huggingface.co/{repo}/resolve/main/{f}?download=true"
        rel = (Path(dest) / f) if dest else Path(f)
        outdir = CKPT / rel.parent
        lines.append(f"{url}\n  dir={outdir}\n  out={rel.name}")

jobs_file = Path("/tmp/aria_jobs.txt")
jobs_file.write_text("\n".join(lines) + "\n")
print(f"queued {len(lines)} files -> {CKPT}")

subprocess.run(
    [
        "aria2c", "-i", str(jobs_file),
        "-x16", "-s16", "-k1M", "-j3", "-c",
        "--auto-file-renaming=false", "--allow-overwrite=true",
        "--console-log-level=warn", "--summary-interval=20",
        f"--header=Authorization: Bearer {TOKEN}",
    ],
    check=False,
)
print("aria2c batch finished")
