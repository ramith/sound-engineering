# The VM's duration = Double(file.length) / rate (AudioViewModel+Playback.swift:93-95).
# A seek to the end (scrubber at 100 %, or the +step key clamped: NowPlayingBar.swift:257/333)
# sends seconds == duration. Enhanced computes frame = AVAudioFramePosition(seconds * rate)
# (truncation, +EnhancedResampler.swift:200 / +PureMode.swift:329) and refuses frame >= length.
# Pure computes llround(seconds * rate) (FileDecodeSource.cpp:988).
import random, math
random.seed(1)
for rate in (44100.0, 48000.0, 88200.0, 96000.0, 192000.0):
    n = 200000; trunc_eq = 0; trunc_lt = 0; rnd_eq = 0
    for _ in range(n):
        L = random.randint(int(rate * 60), int(rate * 900))          # 1 to 15 minute tracks
        sec = L / rate
        f = int(sec * rate)                                # Swift AVAudioFramePosition(Double) truncates
        trunc_eq += (f == L); trunc_lt += (f == L - 1)
        rnd_eq += (round(sec * rate) == L)
    print(f"rate {rate:>8.0f}: seek(to: duration) -> truncated frame == length (Enhanced REFUSES) in {100*trunc_eq/n:.1f}% "
          f"of track lengths; == length-1 in {100*trunc_lt/n:.1f}%; llround == length {100*rnd_eq/n:.1f}%")
# Off-by-one from truncation for ordinary targets: how often does trunc(s*r) differ from round(s*r)
# for a seek target that is an exact frame time (e.g. a resume point saved as frame/rate)?
for rate in (44100.0, 48000.0):
    n = 200000; off = 0
    for _ in range(n):
        k = random.randint(0, int(rate * 600)); s = k / rate
        off += int(s * rate) != k
    print(f"rate {rate:.0f}: a target that IS frame k (s = k/rate) truncates to k-1 in {100*off/n:.2f}% of cases")
