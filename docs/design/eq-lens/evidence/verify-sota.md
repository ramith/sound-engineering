# Verify pass: SOTA review vs `dsp-plan-v2.md` (Reviewer 2)

*2026-10-10. A single, bounded re-check. I read v2, `dsp/v2/results/` and decisions 25–28 (`feat/s10-8-eq` @ c15f183).
New measurements are in this folder and re-run with `sh run_verify.sh` (about 4 min).*

**Labels.** **[M]** measured here · **[A]** the author's v2 measurement · **[O]** my opinion.

## Verdict: **OPEN ITEMS (1)**

Every item from my review is CLOSED; for each one where the author changed my proposal, I accept the change. One item is OPEN: the
founder question about Intensity 0 rests on a false premise (§2).

## 1. My recommendations and corrections

| # | Item | Status | Notes |
|---|---|---|---|
| 1 | 3rd refinement pass | **CLOSED** (5 passes) | **Accept.** My data has 1+3 at 0.27 dB and 1+6 at 0.24–0.25 dB on my hard set [M]. The author's set adds the breaker's 4 commands: 0.402 at 3 passes, 0.322 at 5, 0.345 at 8 [A]. The extra 2 passes cost about 40 µs (≈ 20 µs per pass [M]), so the 0.14 ms total is plausible. |
| 2 | Gated block-spectral predictor | **CLOSED** (1/24-oct) | **Accept 1/24 over my 1/12.** The author's 15 curves include jagged ones (alternating, all −12): 0.112 vs 0.180 dB max [A]. My 1/12 result (0.103) came from 12 smoother curves, so the two agree. The cost, 2.5 MB per 4-minute track, is irrelevant. |
| 2b | Running estimate in R1, pre-analysis later | **CLOSED** (pre-analysis moved into R1) | **Accept.** My own data agrees: the running estimate was off by up to 3.3 dB after 3–10 s, and only reached ≤ 0.45 dB at 30 s [M v1 q4]. The author's 0.67 dB integrated and 2.69 dB in the first 10 s [A] miss the 0.1–0.2 dB target. |
| 3 | Loudness-neutral gain | **CLOSED** (decision 26) | It opens a new question at Intensity 0, which is §2. |
| 4 | Rämö-style gates | **CLOSED** | `EQ_ACGE_Ramo1000` and `EQ_ACGE_Hard` are each ≤ 0.6 dB, against measured 0.440 / 0.322. |
| 5 | Factored or complex \|H\|² in the C++ port | **CLOSED** | Adopted as a port rule. |
| 6 | Analog-Nyquist bells | **CLOSED** (later) | Swappable through the shared coefficient function (F16). |
| Q2 | Double SVF, shared dB ramp | **CLOSED** (SVF kept; the ramp is now S2) | **Accept S2.** I reproduced the claim independently on the author's adversarial pair, frozen path at 48 k, 5 passes, with neutral gains at both ends: **S1 +6.62 dB, S2 0.00 dB**. S1's own S2-adversarial pair gives S1 +1.53 / S2 0.00. Realistic pairs (Off→Warm, Warm→Presence, alt flip) are 0.00 in both [M `v_s1s2_check.txt`]. My v1 test varied only the *structure* under the dB path, so it could not see a swell that lives in the *parameter path*. The author's zipper result, SB within 0.3 dB of SBref on realistic pairs [A], keeps my sideband conclusion. |
| Rej. | FIR, matched, SGE3, neural, per-rate tables, ultrasonic guard, float SVF, vDSP | **CLOSED** | Kept as rejected. |
| §8 | Corrections: "≤ 0.31 everywhere", "3rd pass < 0.02", "±1.2 dB", meter lifetime, the survey's TDF-II inference | **CLOSED** | All corrected in v2 with new data. My note on the survey's 2^(1/6) formula is moot, because v2 never uses it. |

## 2. The trade-off at Intensity 0 with the EQ On (path P1: EQ → limiter)

**Method** [M `v_p1_limiter.txt`, `v_p1_ceiling.txt`]:
- **Limiter:** `cpp/lim_sim.cpp` is a replica of `LimiterModule.h`: 8× polyphase ISP, 3 ms look-ahead, 0.5 ms attack,
  100/500 ms dual release, 50 ms LF hold, −0.27 dB margin. It runs offline.
- **Tracks:** the repo's 7 tracks plus two synthetic look-ahead-limited loud masters:
  - LOUD-A: the band excerpt, HF-poor, −9.2 LUFS;
  - LOUD-B: the generated folkpop, HF-rich, −10.1 LUFS.
- **Curves:** Warm, Presence, Loudness, Tone B+6 Bo−3 P+4 A+6, +12 @ 100 Hz, −12 @ 1 kHz; the design is (b) with 5 passes.
- **Gain:** the *exact* neutral gain. The predictor's ≤ 0.11 dB error comes on top.
- **Reference:** Off is the bit-perfect source (P0).
- **Proxies:**
  - On − Off BS.1770 loudness;
  - limiter gain reduction (GR): maximum depth, plus the share of time beyond 1 dB and beyond 3 dB;
  - output 4× true peak;
  - a distortion proxy: the residual against a 10 Hz-smoothed gain, in dB re signal, inside limited 100 ms windows.

**The premise is false.** The author's measurement (+4.29 dB on 8.9 % of 10 ms *frames* over −1 dBTP) counts only
the frames that are over the ceiling. The real limiter's 500 ms release and LF hold keep it working far longer:
- on LOUD-B with Tone B+6 Bo−3 P+4 A+6: **GR > 1 dB for 74 % of the time and > 3 dB for 26 %, up to 5.6 dB**;
- that limiting removes loudness, so **On is up to 2.75 dB quieter than Off** (p90 1.19 dB over 54 cases).

Founder Q2's option (A), "Accept it. Off and On stay equally loud", is therefore not true on loud masters.
A held Compare at Intensity 0 also stays in P1, so the "Off" it plays is limited: on LOUD-B it is −0.98 dB against the
real original [M].

| Option (54 EQ-On cases) | \|On − Off\| max / p90 | GR max | time GR > 1 dB, worst track | time GR > 3 dB | output TP | distortion proxy, worst | Buildable for R1? |
|---|---|---|---|---|---|---|---|
| (a) accept, −1 dBTP | 2.75 / 1.19 dB | 5.58 | 74 % | 26 % | ≤ −1.21 dBTP | −28.0 dB | yes |
| (b) cap: GR ≤ 2 dB | 3.90 / 1.52 | 2.00 | 42 % | 0 % | ≤ −1.23 | −32.5 | no (see below) |
| (b) cap: GR ≤ 1 dB | 4.66 / 2.25 | 1.00 | 0.1 % | 0 % | ≤ −1.23 | −33.5 | no |
| (c) gentler limiter: 8 ms look-ahead, glide attack, 150/600 ms release | 2.80 / 1.19 | 5.58 | 76 % | 25 % | ≤ −1.13 | −29.2 | yes, but no gain |
| (d) normaliser on | **6.85 / 6.56** | 2.16 | 2.1 % | 0 % | ≤ −1.26 | −32.3 | yes; fairness lost |
| **(e) P1 ceiling −0.1 dBTP** (new) | **2.07 / 0.57** | 4.68 | 67 % | **7.3 %** | ≤ −0.31 | −29.5 | **yes, one parameter** |
| (e) + (b) cap at GR ≤ 2 dB | 3.00 / 0.66 | 2.00 | 14.6 % | 0 % | ≤ −0.33 | −32.5 | needs a peak pass |
| (f) cap on *sustained* GR (p90 over time), −1 dBTP | 3.95 / 1.92 | 3.03 | 6.6 % | 0.13 % | ≤ −1.23 | −32.1 | no |

Notes:
- **Held Compare at Intensity 0** (P1 with the EQ at identity): its mismatch against the real original is ≤ 0.98 dB at
  −1 dBTP and **≤ 0.22 dB at −0.1 dBTP** [M].
- **The cap cannot be predicted from the profile.** I estimated the peak per block from the 1/24-oct profile (source
  4× TP + the block's power gain + the neutral gain). Its error against the measured maximum GR was **−8.2 to
  +3.0 dB** (n = 28) [M]. A capped option therefore needs a curve-specific *time-domain* peak pass (decode, filter,
  4× TP) at each stroke end.
- **Why (e) is safe.** P0 plays the source untouched, and the loud masters here reach −0.2 to +0.8 dBTP. P1 at −0.1 dBTP
  (≤ −0.31 dBTP after the margin) therefore never exceeds what Off already sends to the same device, Bluetooth/AAC
  included [O].
  - If the founder wants −1 dBTP for lossy outputs, that is a policy for P0 and P1 *together*. It should not be a
    penalty on the EQ alone.
  - P2/P3 keep −1 dBTP; the normaliser keeps them far below it.

**Recommendation: (e) for R1.** In the EQ-only path, set the limiter's ceiling to −0.1 dBTP and keep the
loudness-neutral gain uncapped.
- It beats (a) on every proxy:
  - On/Off mismatch p90 1.19 → 0.57 dB;
  - heavy limiting (> 3 dB) 26 % → 7 % of the time on the worst loud master;
  - a held Compare plays the real original within 0.22 dB (from 0.98).
- It is a single parameter on the existing `LimiterParams` for P1.
- **Later:** add the curve-specific peak pass, so the gain is capped where the limiter would exceed 2 dB. That
  removes sustained limiting on loud masters with big boosts (> 1 dB GR, 67 % → 15 % of the time) for at most
  ~1.1 dB more On/Off mismatch on those tracks only [M].
- **Reject:**
  - (a) as written: its premise is false;
  - (c): no measurable gain;
  - (d): 6.9 dB of mismatch against the bit-perfect Off.

**In plain words.** When the EQ plays without the enhancer, let it peak as high as the original song already does,
just under 0 dB, instead of 1 dB lower. Off and On then stay within about half a dB of each other on almost every
song, and the safety limiter squeezes loud, bass-boosted masters far less. On a few very loud masters, a big boost
still has to be either squeezed or turned down; turning it down cleanly needs a later peak pre-scan.

*Caveats.* Both loud masters are synthetic (look-ahead limited to −0.3 dBFS sample peak), and only 2 of the 9 tracks
are loud masters. The proxies stand in for a listening test; they do not replace one [O].

## 3. New issues in v2 (BLOCKER/MAJOR only, within my lens)

- **MAJOR, the same as §2: founder question Q2 is framed on a false premise.** Option (A), "Off and On stay equally
  loud", fails by up to 2.75 dB, and the frame-based metric hides 74 % time-in-limiting. The question must be
  restated with the GR-time and mismatch numbers above, and (e) offered before it is put to the founder.
- No other BLOCKER or MAJOR issues:
  - S2, the 5-pass solver and the 1/24-oct predictor reproduce or agree with my data.
  - The CPU figures (2.67 % ramping, 2.00 % settled at 192 k × 8) match mine.

## 4. Files

- `verify.md` (this file) and `run_verify.sh`;
- `v_s1s2_check.py`, `v_p1_limiter.py`, `v_p1_ceiling.py`, `cpp/lim_sim.cpp`;
- `results/v_s1s2_check.txt`, `results/v_p1_limiter.{txt,json}`, `results/v_p1_ceiling.txt`.

---

**Verdict: OPEN ITEMS (1).**
1. My items 1–6, Q2, the rejections and the corrections are all CLOSED. I accept 5 passes, 1/24-oct, pre-analysis in R1 and S2 (reproduced: S1 +6.62 dB vs S2 0.00).
2. OPEN: the Intensity-0 founder question's premise is false. The real limiter keeps > 1 dB GR for up to 74 % of the time, and On ends up to 2.75 dB quieter than Off.
3. Options measured: accept (a) 2.75 / p90 1.19 dB mismatch; normaliser (d) 6.9 dB; gentler limiter (c) no gain; caps (b) 3.9–4.7 dB and not predictable from the profile (−8 to +3 dB error).
4. Recommended for R1: (e) set the EQ-only path's limiter ceiling to −0.1 dBTP. Mismatch p90 0.57 dB, > 3 dB limiting 26 % → 7 %, held Compare within 0.22 dB of the original, and never above what Off already plays.
5. Later: a curve-specific peak pass to cap the limiter's GR at 2 dB on loud masters (≤ 1.1 dB more mismatch there).
