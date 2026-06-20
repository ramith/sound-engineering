# test audio

Drop your own tracks here to try the remaster. Anything ffmpeg can read works
(`.wav`, `.flac`, `.mp3`, `.m4a`, `.aac`, ...). This folder is git-ignored except this file.

```bash
# from research/legacy-remaster-poc/, with the venv active:
legacy-remaster remaster data/your_old_track.m4a -o out/your_track.remastered.wav --plots out/plots -v

# match the tonal balance to a modern track you like:
legacy-remaster remaster data/old.m4a --reference data/modern_reference_track.flac --plots out/plots

# if the track has a quiet intro/outro, point de-hiss at it for a cleaner noise profile:
legacy-remaster remaster data/old.mp3 --noise-start 0.0 --noise-dur 1.5
```

Tip: best de-hiss comes from giving an explicit noise-only segment (`--noise-start/--noise-dur`).
Without one, a blind percentile estimate is used, which is safe but can slightly dull very
sustained tones.
