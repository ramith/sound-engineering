# The bridge's own reader: fixtures (R1.1-B sound fix round, lane F1)

Self-made, public domain, generated from ffmpeg's `sine` source. The gate never runs `ffmpeg`; the files are
checked in. Each is what Apple's decoder does with a kind of file the app meets in the wild.

| File | What Apple's decoder does | Used by |
|---|---|---|
| `tone-ac3-stereo-44k-part1.m4a`, `-part2.m4a` | 1 s each of one 440 Hz tone (the first and the second second), stereo, 44.1 kHz, AC-3 at 64 kb/s in MP4 (~9 KB). `length` says 44 544 frames; the decoder delivers 44 256, then nothing (288 short, as every AC-3 / E-AC-3 file in the test corpus). | `ReaderSeamTests`: a short-read file joins the next in one stream (LOW-6) |
| `surround-5.1-48k.opus` | 0.2 s of a tone on six channels, Opus at 96 kb/s (~3 KB). macOS 26 opens stereo Opus but refuses multichannel: `AVAudioFile` fails with `'fmt?'` (KI-LIB-12). | `UnplayableFileTests`: a variant macOS can't decode is said so (LOW-3) |

Made with:

```
ffmpeg -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=2" \
  -af "atrim=start=0:end=1,asetpts=PTS-STARTPTS" -ac 2 -c:a ac3 -b:a 64k tone-ac3-stereo-44k-part1.m4a
ffmpeg -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=2" \
  -af "atrim=start=1:end=2,asetpts=PTS-STARTPTS" -ac 2 -c:a ac3 -b:a 64k tone-ac3-stereo-44k-part2.m4a
ffmpeg -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=0.2" \
  -af "pan=5.1|FL=c0|FR=c0|FC=c0|LFE=c0|BL=c0|BR=c0" -c:a libopus -b:a 96k surround-5.1-48k.opus
```

The 48 kHz short-read file (mono AC-3) is the break-it's: `Tests/Fixtures/breakit-sound/tone-ac3-mono-48k.m4a`.
