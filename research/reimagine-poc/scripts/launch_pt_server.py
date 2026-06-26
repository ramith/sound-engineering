#!/usr/bin/env python3
"""Launch the ACE-Step API server with MLX fully DISABLED (PyTorch DiT + VAE + LM).

Diagnostic: base-model output is garbled on the MLX path. This forces the pure-PyTorch
path to isolate whether MLX is the culprit. We monkeypatch mlx_available()->False BEFORE
service init (so MLX DiT + MLX VAE both skip), and pass --backend pt for the LM.
"""
import os
import sys

# 0) Stay offline so the PyTorch DiT path uses local base weights instead of
#    re-downloading the full 10 GB "main" bundle (turbo + 1.7B we don't need).
os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
os.environ.setdefault("HF_DATASETS_OFFLINE", "1")
os.environ.setdefault("ACESTEP_LM_BACKEND", "pt")  # CLI --backend didn't take; force via env

# 1) Force MLX off everywhere it is gated on availability.
import acestep.models.mlx as _mlx
_mlx._MLX_AVAILABLE = False
_mlx.mlx_available = lambda: False
try:
    _mlx.is_mlx_available = lambda: False  # underlying probe, if referenced directly
except Exception:
    pass

# 2) Launch the normal CLI with base model, API enabled, PyTorch LM backend.
sys.argv = [
    "acestep",
    "--config_path", "acestep-v15-base",
    "--enable-api",
    "--backend", "pt",
    "--port", "8001",
]
from acestep.acestep_v15_pipeline import main
sys.exit(main())
