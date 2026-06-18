# test-data/

Working directory for the C++ DSP test harness's audio fixtures.

The harness (`scripts/build-null-test.sh` → `Tests/DSPKernelNullTest`) writes its WAV/PCM
fixtures **here**, not in `/tmp`. The compile passes the absolute path of this directory as
`-DADAPTIVESOUND_TEST_DATA_DIR=...`; tests build fixture paths from that macro (with a
`"test-data"` relative fallback in `Tests/TestSupport.h` so clang-tidy and other compiles
still resolve a path).

The fixtures are **generated deterministically at test runtime** (via `writeWav16` /
`writeWav24` / `writeWavFloat32`), so they are git-ignored — only this `README.md` is tracked,
which keeps the directory present after a fresh clone. A few tests intentionally reference an
**absent** file (e.g. open-failure paths); those are never written, so they stay absent here
exactly as they did under `/tmp`.

Do not commit generated fixtures; do not point tests back at `/tmp`.
