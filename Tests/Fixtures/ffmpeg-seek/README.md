# FFmpeg seek fixture (R1.1-A, council C-35)

`start-offset.nut` — 0.5 s of seeded white noise (mono, 44.1 kHz, FLAC in NUT) whose stream starts at
**1.5 s**, in a 1/44100 time base: FFmpeg's timestamps count from the stream's `start_time`, the app's
frames from 0, and a seek has to add the one to the other to land on the right sample. Apple's decoder
can't open NUT, so it is also a real "only FFmpeg reads it" file. Seeded noise, so a seek that lands on
the wrong sample can't match by repetition. Self-made, public domain, ~47 KB.

Checked in and authoritative: the gate never runs `ffmpeg`. Made with:

```
ffmpeg -f lavfi -i "anoisesrc=d=0.5:c=white:seed=7:a=0.005:r=44100" -ac 1 -c:a flac \
  -output_ts_offset 1.5 Tests/Fixtures/ffmpeg-seek/start-offset.nut
```

Used by the C++ null test (`FileDecode_Seek_FFmpegHonoursStreamStart`,
`FileDecode_Seek_RefusedKeepsBufferedAudio`, `Tests/FileDecodeTests.inc`).
