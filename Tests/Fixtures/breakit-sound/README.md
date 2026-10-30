# Break-it fixture: a short-read AC-3 file (R1.1-B sound break-it)

`tone-ac3-mono-48k.m4a` — 2 s of a 440 Hz sine, mono, 48 kHz, AC-3 at 64 kb/s in MP4 (~17 KB). Self-made,
public domain. Apple's decoder reports `length` 96 768 frames but delivers 96 480, then the next read throws —
the same short read every AC-3 / E-AC-3 file in the test corpus shows (288 frames short). The gate never runs
`ffmpeg`; the file is checked in. Made with:

```
ffmpeg -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=2" -ac 1 -c:a ac3 -b:a 64k \
  Tests/Fixtures/breakit-sound/tone-ac3-mono-48k.m4a
```

Used by BI-S05 (`Tests/AdaptiveSoundTests/BreakItSoundBridgeTests.swift`): the passthrough's end of track must not
come before the track's last frame has played.
