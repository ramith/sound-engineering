# FFmpeg "works with any FFmpeg": research summary (2026-10-22)

The research agent had no write tool. It delivered this report as a message, and the coordinator saved it here, summarised with its key evidence. The full text is in the coordinator's conversation transcript (session 737ceb91). Evidence labels: [opened] = read this session; [search] = from search summaries only; [unverified] = inference or memory.

## Recommendation
**Run the user's installed `ffmpeg` and `ffprobe` as child processes, instead of `dlopen`-ing the libraries.** This covers both decode and metadata.

How it works:
- **Decode:** `ffmpeg -ss T -i file -map 0:a:0 -f f32le -`, piped into the existing SpscRing decode thread.
- **Metadata:** `ffprobe -of json`, plus one `ffmpeg … -c copy -f image2pipe` call for cover art.
- **Finding the tools:** only at the vetted fixed paths (`/opt/homebrew/bin`, `/usr/local/bin`), with the same owner and permission checks FFmpegLoader uses for libraries.

Why:
- It is the only option that works with ANY FFmpeg, including future majors. Command-line flags change far more slowly than struct layouts.
- It removes the vendored headers, `__has_include`, per-major builds, baked-in majors, Homebrew headers in CI, the `disable-library-validation` entitlement and the dlopen hardening.
- FFmpeg's parsers run out of process, which improves KI-SEC-01.
- The licensing is clean: FFmpeg is a separate program.

Weakness: no mainstream player decodes in real time this way. It is acceptable here because FFmpeg is an opt-in fallback for files Apple can't open.

**A spike must prove first:**
- sample-accurate seek (input-side `-ss`, accurate_seek) [unverified];
- gapless seams and Opus pre-skip parity with today;
- channel order;
- `bits_per_raw_sample` via ffprobe;
- pipe throughput at 8 ch / 192 kHz.

**Plan B** if the spike fails: vendored headers per major plus one backend per major (the Firefox/Audacity pattern). That reaches only the majors we ship headers for.

## How reputable projects do it
- **Firefox** [opened]: `dom/media/platforms/ffmpeg/`. `FFmpegRuntimeLinker` tries `libavcodec.<major>` newest first. `FFmpegLibWrapper` reads `avcodec_version()` and maps the major to the symbol set it expects. The `FFmpegDecoderModule<V>` template is compiled per major against vendored, trimmed headers (libavcodec + libavutil; `ffmpeg57`…`ffmpeg63`), with `COPYING.LGPLv2.1` and the LGPL banners kept. An unknown major gets an "Unknown" status and is not used.
- **Audacity** (GPL) [search]: function-pointer tables, with per-major implementation folders over vendored headers (avformat 55–61). It doesn't bundle FFmpeg, citing patents.
- **Qt Multimedia** [opened]: links at build time; requires the same major at deploy; falls back to the native backend.
- **mpv** [search]: refuses any FFmpeg other than its build's. **gst-libav** [search]: pinned per release.
- **Chromium, VLC, Kodi:** ship their own FFmpeg [unverified].
- **Conclusion:** no reputable in-process loader supports an unseen major. "Any FFmpeg" in-process really means "any major we shipped headers for".

## Licensing
- FFmpeg is LGPL-2.1+ (GPL with `--enable-gpl`) [opened: LICENSE.md, ffmpeg.org/legal.html]. The compliance duties fall on whoever DISTRIBUTES FFmpeg binaries (Homebrew or the user), not on us.
- Running or loading the user's own install is fine. The subprocess design makes this clear-cut.
- **Vendoring the LGPL headers in an Apache-2.0 repo** (plan B only):
  - It is defensible through LGPL-2.1 §5 (struct layouts, accessors, small macros and inlines) and Firefox's practice: keep the banners, ship COPYING.LGPLv2.1, add a NOTICE line, never edit the files.
  - No source rules on it, so it is a risk to accept knowingly. This is not legal advice. The gnu.org text couldn't be opened (HTTP 429).

## What our backend uses today
- **Libraries:** libavformat, libavcodec, libavutil and libswresample, with 30 dlsym'd functions.
- **Structs and fields:**
  - `AVFormatContext`: streams, nb_streams, duration, metadata;
  - `AVStream`: codecpar, time_base, start_time, disposition, attached_pic;
  - `AVCodecParameters`: sample_rate, ch_layout.nb_channels, bits_per_raw_sample, codec_id;
  - `AVCodecContext`: sample_rate, ch_layout, sample_fmt, bits_per_raw_sample;
  - `AVFrame`: nb_samples, extended_data, best_effort_timestamp, pts;
  - `AVPacket`: stream_index, size, data;
  - `AVDictionaryEntry`.
- **Macros and helpers:** av_q2d, AV_NOPTS_VALUE, AVERROR, AVSEEK_FLAG_BACKWARD, AV_TIME_BASE, AV_DICT_IGNORE_SUFFIX, AV_DISPOSITION_ATTACHED_PIC, AV_CODEC_ID_MJPEG/PNG, AVMEDIA_TYPE_AUDIO.
- **API floor:** it needs `ch_layout` and `swr_alloc_set_opts2`, which exist from FFmpeg 5.1 (libavcodec 59) onward [unverified].
- **Majors:** FFmpeg 9.0 = libavcodec 63 / libavutil 61 [opened]; 8.1 = libavcodec 62 [opened]. 7.1 = 61, 6.1 = 60, 5.1 = 59, 4.4 = 58 [memory].
- **Current releases:** 9.0.2 (2026-09-18), 8.1.3, 8.0.3, 7.1.5, 6.1.6, 5.1.10, 4.4.8 [opened]. A new major arrives about once a year.

## Options

| Option | Works with | Effort | Verdict |
|---|---|---|---|
| (c) CLI subprocess | Any FFmpeg ≥ the features we use | ~1 sprint, including a day-1 spike | **Recommended** |
| (a) Vendored headers per major + a backend per major | Majors 59–63 only; each new major needs an app release | ~1.5–2 sprints + ~1 day per major | Plan B |
| (b) A version-independent C surface | Not feasible: FFmpeg's API is struct-based, and nobody does it | n/a | Rejected |
| (d) Bundle a pinned FFmpeg | One major; we take on the compliance, notarisation and patching | n/a | Not recommended (not "any") |

## Testing
- **Per-major FFmpeg builds:** minimal ffmpeg/ffprobe for each tested major (5.1, 6.1, 7.1, 8.x, 9.x), built from SHA-256-pinned release tarballs (`--disable-everything` plus the fixture codecs, `--disable-gpl`), cached by hash. Never Homebrew, and never `ffmpeg@N` as a pin.
- **A matrix job per major:** runs with `ADAPTIVESOUND_DECODER=ffmpeg` and compares PCM and tags to checked-in expected results.
- **No dependence on the runner's FFmpeg:** a test-only tool-path override, so the gate never touches what is installed.
- **Remove:** `brew install ffmpeg || true` (strict-ci.yml ~57, release.yml ~46) and the `-isystem /opt/homebrew/include` flag (Package.swift ~363).
- **Keep:** one "no FFmpeg" job, to prove the Apple-only path.

## Sources (opened)
- gecko-dev `dom/media/platforms/ffmpeg/{FFmpegRuntimeLinker.cpp,FFmpegLibWrapper.cpp,FFmpegDecoderModule.h,FFmpegRuntimeLinker.h}`, plus the searchfox listings for `ffmpeg/` and `ffmpeg62/include`, and `ffmpeg61/include/libavcodec/avcodec.h`;
- doc.qt.io/qt-6/qtmultimedia-index.html;
- ffmpeg.org/legal.html, FFmpeg LICENSE.md and ffmpeg.org/download.html;
- FFmpeg release/9.0 and 8.1 `version_major.h` / `version.h`.

Search-only: Audacity support and doxygen pages, the mpv README mirror, the LFS gst-libav page, and the LGPL discussions.
