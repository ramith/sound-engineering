# EQ rebuild: literature survey (verified in session, 2026-10-09)

Scope: the algorithms behind AdaptiveSound's EQ rebuild. That covers a 31-band ISO third-octave cascade GEQ (±12 dB, 44.1–192 kHz, ≤8 ch), automatic headroom, an honest played-response graph, zipper-free drags, five Tone macros, and a level-matched Compare.

**Rule followed:** I opened every source marked "Yes" in this session and took the numbers from the source itself, not from memory.

**Verified column legend**

| Mark | Meaning |
|---|---|
| **Yes-full** | Opened the full text (PDF or HTML). |
| **Yes-abs** | Opened the publisher, repository or archive landing page (abstract and metadata). |
| **Partial** | Primary source not opened. Numbers come from a verified secondary source, which is named. |
| **No** | Not verified: the source was paywalled, blocked (403) or missing. Treat any numbers as unconfirmed. |

Notes marked **"(our computation)"** are my own arithmetic, not a published result.

---

## 1. Graphic EQ design with band interaction

| Paper | Method | Reported numbers (quoted/transcribed from source) | Link (opened) | Verified? |
|---|---|---|---|---|
| Välimäki & Liski, "Accurate Cascade Graphic Equalizer", *IEEE Signal Processing Letters* 24(2):176–180, 2017, doi 10.1109/LSP.2016.2645280 | Octave cascade with **one Orfanidis 2nd-order peak/notch per band**. Bandwidth is set so the gain at neighbouring centres is c·g (c = 0.3). Interaction matrix B is (2M−1)×M, with extra points at geometric-mean midpoints. Prototype gain g_p = 17 dB. LS solve via pseudoinverse, then **one iteration** (B₁ is rebuilt from the first-pass gains). Top three octave bandwidths are hand-reduced (5580/9360/12160 Hz). fs = 44.1 kHz. | Table I, max error in dB, OJ / EQ4 / PGE / **proposed**: zigzag 1.2 / 1.8 / 0.91 / **0.25**; every-third-down 0.67 / 1.2 / 0.76 / **0.52**; OJ worst case 2.3 / 1.5 / 0.69 / **0.49**. Text: "maximum error at the command points is 0.63 dB … and 0.49 dB". "Tested extensively, and its error has not exceeded 1 dB at the command or extra points or between them when neighboring command gains are the same." Table II ops/sample: OJ 90, EQ4 290, PGE 161, proposed 90. Table III MATLAB update time: OJ 0.045 ms, EQ4 0.0082 ms, PGE 19 ms, proposed 2.2 ms. "44% more efficient" than accurate parallel GEQ. | https://acris.aalto.fi/ws/portalfiles/portal/27113913/ELEC_valimaki_et_al_Accurate_cascade_graphic.pdf ; landing https://research.aalto.fi/en/publications/accurate-cascade-graphic-equalizer | **Yes-full** (author manuscript) |
| Liski & Välimäki, "The Quest for the Best Graphic Equalizer", *DAFx-17*, Edinburgh, 2017, pp. 95–102 | Extends ACGE to **31 third-octave bands**: 61 design points (centres plus geometric means), B_m = (2^(1/6) − 2^(−1/6))·ω_c ≈ 0.4662·ω_c. **c = 0.4** (c = 0.3 gave filters that were too narrow), g_p = 17 dB, one iteration. **Six highest bandwidths hand-tuned** (Table 1: 6350→2846, 8000→3502, 10080→4253, 12700→5038, 16000→5689, 20160→5573 Hz). Proposes testing with ±12 dB "binary" hard settings (2¹⁰ = 1024 for octave; 2³¹ is impractical for third-octave). | Table 2, third-octave max error PGE vs **ACGE3**: zigzag 0.65 vs **0.41 dB**; hard case **0.66** vs 0.98 dB. Table 3 ops/sample: PGE 496 (248 add + 248 mul) vs ACGE3 **279** (124 + 155). Gain-update time (MATLAB, average of 1000 random): PGE **24 ms**, ACGE3 **6.0 ms**. Octave: after 1 iteration the error "saturates at 0.87 dB" (hardest case, Fig. 7). With c = 0.3 the all-+12 dB case exceeds 1 dB at HF (Fig. 9a). | https://dafx.de/paper-archive/details/Ycir51R86FWcfPNqrjV2kQ → https://dafx.de/paper-archive/2017/papers/DAFx17_paper_94.pdf | **Yes-full** |
| Companion code for DAFx-17 (`acge3.m`, `interactionMatrix.m`, `pareq.m`) | MATLAB reference implementation: `fs = 44.1e3`, `gw = 0.4` ("parameter c"), 31 centres 19.69 Hz–20.16 kHz, 61 points, "Iterate once". `pareq.m` follows Orfanidis, *Introduction to Signal Processing*, p. 594. | No license is stated in the directory or the readme. | http://research.spa.aalto.fi/publications/papers/dafx17-geq/ (listing, readme.txt, acge3.m opened) | **Yes-full** |
| Liski, Rämö & Välimäki, "Graphic Equalizer Design with Symmetric Biquad Filters", *IEEE WASPAA 2019*, pp. 55–59, doi 10.1109/WASPAA.2019.8937168 | Octave GEQ. Band filters are **symmetric on a log axis up to Nyquist**, which fixes the asymmetry of earlier designs. WLS solve with **per-band prototype gains** and an optional iteration. | Abstract: max error **below 1 dB** at centres and between equal neighbours. Claims "the most accurate graphic equalizer design to date". | https://research.aalto.fi/en/publications/graphic-equalizer-design-with-symmetric-biquad-filters | **Yes-abs** |
| Rämö, Liski & Välimäki, "Third-Octave and Bark Graphic-Equalizer Design with Symmetric Band Filters", *Applied Sciences* 10(4):1222, 2020, doi 10.3390/app10041222 | **SGE3**: Orfanidis-derived symmetric band filters with **adjustable Nyquist gain**. The Nyquist gain is a cubic polynomial in peak gain for bands 23–31; bands 1–22 stay ≈ 0 dB at Nyquist. The Nyquist targets come from a 10 MHz oversampled analog-like filter. WLS with 61 points, 1 iteration, g_p = 11 dB, c = 0.38, uniform weights. Bandwidths of bands 17–31 were reduced "due to frequency warping close to the Nyquist limit". fs = 44.1 kHz. Parameters were tuned over 8192 command settings. **NSGE3** is an MLP (31-62-31-31) trained on 1500 pairs. | Table 5, 10,000 random settings, max (mean-max): **ACGE3 0.97 (0.53) dB**, NGEQ3 1.05 (0.54), **SGE3 0.81 (0.50)**, NSGE3 0.86 (0.50). The worst SGE3 case is at 16,443 Hz, between two +12 dB top bands. Zigzag ±12 dB gives ≈ 0.42 dB at 20 Hz. Table 7 (MATLAB, 2017 MacBook Pro i7, 100k runs): SGE3 gains 408 µs + coefficients 126 µs = **534 µs**; NSGE3 5.1 + 126 = **131 µs**. The paper links MATLAB scripts (link not opened). | https://acris.aalto.fi/ws/portalfiles/portal/41964159/Third_octave_and_Bark_graphic_equalizer_design.pdf ; https://research.aalto.fi/fi/publications/third-octave-and-bark-graphic-equalizer-design-with-symmetric-ban/ | **Yes-full** |
| Välimäki & Rämö, "Neurally Controlled Graphic Equalizer", *IEEE/ACM TASLP* 27(12):2140–2149, 2019, doi 10.1109/TASLP.2019.2935809 | Octave ACGE in which an MLP (one hidden layer, 20 neurons) predicts the filter gains, removing the matrix inversion and iteration. | Abstract: "reduces the computing time by 99.6% in comparison to the least-squares design … and contributes an approximation error of less than 0.1 dB". It also notes that a single-biquad-per-band accurate design "was only introduced in 2017". | https://acris.aalto.fi/ws/portalfiles/portal/40860405/V_lim_ki_Neurally_Controlle_Graphic_Equalizer.08809819_1.pdf | **Yes-full** (pp. 1–2 read) |
| Rämö & Välimäki, "Neural Third-Octave Graphic Equalizer", *DAFx-19*, Birmingham, 2019 | MLP with two hidden layers (62 and 31 units) imitating the third-octave LS design. | "Maximum error of 1.2 dB". Gain computation is "over 350 times faster". | https://dafx.de/paper-archive/details/LjIjfHTZj3NTbKcGFC8R8g | **Yes-abs** |
| Rämö, Välimäki & Bank, "High-Precision Parallel Graphic Equalizer", *IEEE/ACM TASLP* 22(12):1894–1904, 2014 | **PGE**: Bank's fixed-pole parallel 2nd-order sections with **2M poles** (extra poles at geometric means plus one below the lowest band). Needs a dense interpolated target and a minimum-phase target via FFT/Hilbert, with a weighted LS (matrix inversion) **on every gain change**. | Via secondary sources: octave PGE max error 0.69–0.91 dB, 161 ops (SPL-17 Table I/II); third-octave 0.65/0.66 dB, 496 ops, 24 ms update (DAFx-17). Review example: ±10 dB octave, max 0.64 dB at 31.5 Hz. Primary abstract (search index only): "0.00 to 0.75 dB", "+23%" ops vs Regalia–Mitra. | https://research.aalto.fi/en/publications/high-precision-parallel-graphic-equalizer (citation only) | **Partial** (via SPL-17, DAFx-17, Välimäki & Reiss) |
| Bank, "Perceptually motivated audio equalization using fixed-pole parallel second-order filters", *IEEE SPL* 15:477–480, 2008 | Fixed-pole parallel filters: poles are fixed on a log grid and the numerators are solved by linear LS. | Abstract via search only: 33% fewer ops than Kautz. The code page (opened) offers MATLAB `parfilt*.m`, has **no GEQ code**, and states "Non-commercial use permitted". | http://home.mit.bme.hu/~bank/parfilt/ | **No** for the paper; **Yes** for the code page |
| Oliver & Jot, "Efficient Multi-Band Digital Audio Graphic Equalizer with Accurate Frequency Response Control", *AES 139th Conv.*, New York, Oct 2015 | Cascade of biquads with interaction compensation. Per the review: sets **G₀ to the median command gain** and offsets the bands. | From SPL-17 Table I: 1.2 / 0.67 / **2.3 dB** max error; "worst case command gain error of 2.28 dB occurs at 1.0 kHz"; 90 ops/sample; 0.045 ms update. MathWorks `graphicEQ` (opened) uses [Oliver & Jot] for EQOrder = 2, with a gain correction that is "independent of the requested gains", so it does not adapt to the user's settings. | https://www.mathworks.com/help/audio/ref/graphiceq-system-object.html (secondary) | **Partial** (primary blocked) |
| Abel & Berners, "Filter Design Using Second-Order Peaking and Shelving Sections", *ICMC 2004*, Miami | Shows that peaking and shelving sections are "nearly self-similar on a log magnitude scale". dB magnitude responses are used as LS basis functions, giving a GEQ that interpolates the band gains and a Bark-weighted fit. **This is the root idea of ACGE.** | No numbers in the abstract. | https://ccrma.stanford.edu/~jos/mus423h/Filter_Design_Method_Using.html (abstract) | **Yes-abs** (primary PDF 403) |
| Holters & Zölzer, "Graphic Equalizer Design Using Higher-Order Recursive Filters", *DAFx-06*, Montreal, pp. 37–40 | Higher-order (8th-order, M = 4) **band-shelving** filter per band, i.e. 4 biquads/band. Bands are nearly independent, so **no interaction solve** is needed. fs = 48 kHz; octave and 30-band third-octave. | Third-octave, all +12 dB: "ripple stays below 1 dB up to 10 kHz and grows toward the highest bands". Octave: "only in the transitional region between ninth and tenth band, the deviation … exceeds 1 dB. This is an artifact of the bilinear transform". This is mitigated by lowering the top band edge (18.5 kHz octave, 20.5 kHz third-octave). | https://dafx.de/paper-archive/2006/papers/p_037.pdf | **Yes-full** |
| Schlecht, Sinjanakhom & Välimäki, "Multi-shelf graphic equalizer", *Signal Processing* 226:109630, 2025 | Cascade of **shelving** filters (variable order 1–4) with log-scale LS. | Abstract: peak-filter GEQs are "typically limited to 24 dB"; the shelf GEQ covers "over 60 dB". Conclusion: it "performs poorly with rapidly varying responses, whereas the state-of-the-art SGE remains superior in such cases". Code on GitHub (not opened). | https://acris.aalto.fi/ws/portalfiles/portal/154638738/1-s2.0-S0165168424002494-main.pdf | **Yes-full** (pp. 1, 7–8) |
| Antonelli, Liski & Välimäki, "Sparse Graphic Equalizer Design", *IEEE SPL* 29:1659–1663, 2022 | OMP plus LP selects a minimal set of active bands, followed by an LS gain solve. HF bandwidths are gain-dependent to match an analog prototype. | Accuracy is "approximately the same or better" than the non-sparse state of the art, with lower load when few bands are active. | https://research.aalto.fi/fi/publications/sparse-graphic-equalizer-design/ | **Yes-abs** |
| Välimäki & Reiss, "All About Audio Equalization: Solutions and Frontiers", *Applied Sciences* 6(5):129, 2016 | Review. Covers cascade GEQs (worked 10×10 B matrix), parallel GEQs, shelving and tone controls, and semantic EQ. | Octave cascade with B⁻¹: max error 0.5 dB at 125 Hz, but "peak-to-peak … ripple (about 2 dB)". PGE ±10 dB example: largest command-point deviation 0.64 dB. Code: code.soundsoftware.ac.uk/projects/allaboutaudioeq (not opened). | https://acris.aalto.fi/ws/portalfiles/portal/9936551/applsci_06_00129.pdf | **Yes-full** (relevant pages) |
| Bruschi, Cecchi, Nicolini & Välimäki, "Real-Time Implementation of a Linear-Phase Octave Graphic Equalizer", *DAFx-24*, Guildford | Linear-phase octave GEQ built from IFIR filters; a real-time plugin; MUSHRA-style test against a filterbank EQ. | "Reasonable latency". No figures on the landing page. | https://dafx.de/paper-archive/details/UclKEJ7mrYmGWM7LzoD1Pw | **Yes-abs** |
| Välimäki, IEEE SPS webinar "Graphic Equalizers", 20 May 2026 | Talk listing. | "Today, we can design highly accurate cascade or parallel graphic EQ filters"; "The choice of parametric EQ design significantly impacts the accuracy". | https://signalprocessingsociety.org/events/sps-sltcaasp-webinar-graphic-equalizers | **Yes-abs** |

**Comparison for a third-octave, ±12 dB design (best available verified figures)**

| Design | Max error (dB) | Filters per channel | Ops/sample/ch | Reported update cost | Per-drag real-time fit | Open reference code |
|---|---|---|---|---|---|---|
| ACGE3 (DAFx-17) | 0.41 zigzag, 0.98 hard; **0.97** over 10k random (per Rämö 2020) | 31 biquads | 279 | 6.0 ms (MATLAB) | Yes. One small LS and one iteration. | MATLAB, verified, **no license** |
| SGE3 (Rämö 2020) | **0.81** over 10k random (mean-max 0.50) | 31 biquads (Nyquist-gain form) | ≈ same as ACGE3 | 0.53 ms (MATLAB) | Yes | MATLAB link in paper (not opened) |
| NSGE3 (neural) | 0.86 | 31 biquads | same | 0.13 ms | Yes, but needs training and is a black box | — |
| PGE (2014) | 0.65–0.66 | 62 parallel 2nd-order | 496 | 24 ms (MATLAB) | Heavier: FFT/Hilbert plus inversion per change | Not verified |
| Oliver–Jot (2015) | up to 2.3 (octave) | 10 biquads (octave) | 90 | 0.045 ms | Yes, but **not accurate enough** | MathWorks implements it |
| Holters–Zölzer (2006) | < 1 below 10 kHz, > 1 near top bands | 4 biquads/band (124 total) | ~4× ACGE | None needed (independent bands) | Yes | — |
| Multi-shelf (2025) | Better for smooth, wide-range targets; worse for zigzag | variable | variable | LS | Yes | GitHub (not opened) |

**What this means for our plan**
- The literature supports the candidate. ACGE3 is a sound baseline: 31 biquads/ch, LS plus one iteration, < 1 dB on the published tests.
- SGE3 (Rämö 2020) is the measured state of the art for one biquad per band: 0.81 vs 0.97 dB on the same 10k-setting test. Design the band-filter formula as a swappable component.
- The design cost is negligible on a Mac, so neural gain prediction is not needed. **(our computation)**: a 31×61 mat-vec, 61×31 magnitude evaluations and a 31×31 solve per update come to roughly 10⁴–10⁵ flops.
- "< 1 dB" is measured only at the command points, and at midpoints only when neighbours are equal. The ripple between points is unbounded by the method, so the graph must plot the true |H| on a dense grid (already planned).
- Reimplement from the papers. The DAFx-17 MATLAB has no license, and Bank's code is non-commercial only.

---

## 2. Near-Nyquist bell and shelf design (cramping)

| Paper | Method | Reported numbers | Link (opened) | Verified? |
|---|---|---|---|---|
| Orfanidis, "Digital parametric equalizer design with prescribed Nyquist-frequency gain", *JAES* 45(6):444–455, 1997 | Modifies the analog prototype so the digital filter has a **prescribed Nyquist gain G₁** (not forced to 0 dB). | Formulas are reproduced in Vicanek §3.3, with the constraint that the "center frequency must be chosen at least half a bandwidth below the Nyquist frequency: f₀ < (1 − 1/(2Q)) f_Ny". | (primary not opened) | **Partial** (via Vicanek 2016, Rämö 2020) |
| Massberg, "Digital Low-Pass Filter Design with Analog-Matched Magnitude Response", *AES 131st Conv.*, paper 8551, 2011 | Builds a modified (shelving-based) prototype before the bilinear transform so the magnitude matches the analog filter near Nyquist. Low-pass focus. | Vicanek §3.4 gives the full recipe (g₁ = analog gain at Nyquist, etc.). There are no error figures in what I opened. | (AES page 403) | **Partial** (via Vicanek 2016) |
| Vicanek, "Matched Second Order Digital Filters", note, 14 Feb 2016 | Closed-form "matched" biquads. Poles come from **impulse invariance** ("to avoid peak narrowing towards Nyquist"). Numerators are matched at DC and at ω₀ (peaking: unity at DC, G at ω₀, extremum at ω₀). Covers LP/HP/BP/peaking. | Bilinear transform: "frequency warping towards the Nyquist frequency … a narrowing of the resonant peak"; "Oversampling provides remedy but at a high CPU cost". Matched LP: "its computation requires double precision". Figures compare matched and BLT peaking EQs at f₀ = 0.0512…0.8 (Q = 1, −20 dB). No tabulated error. | https://www.vicanek.de/articles/BiquadFits.pdf | **Yes-full** |
| Clark, Ifeachor, Rogers & Van Eetvelt, "Techniques for generating digital equalizer coefficients", *JAES* 48(4):281–298, 2000 | Comparison of coefficient-calculation methods. | Not obtained. | — | **No** |
| Darabundit & Abel, "Conformal Maps for the Discretization of Analog Filters Near the Nyquist Limit", *DAFx-21* (DAFx20in21), Vienna | Peaking and shelving **conformal maps** applied before the bilinear transform. Order-preserving and parameterizable. | "Provides a close match to the original analog frequency response below half the sampling rate". "Prewarping allows for some correction … but it will not completely correct for frequency warping near the Nyquist limit". Aimed at "time-varying" filters and "many different sampling rates". | http://dafx2020.mdw.ac.at/proceedings/papers/DAFx20in21_paper_15.pdf | **Yes-full** (p. 1) |
| Darabundit, Abel & Berners, "Nyquist Band Transform", *JAES* 70(9):674–689, 2022 | Generalisation of the above (NBT). | Abstract via search only: "little frequency warping". | (AES page 403) | **No** |
| Rämö et al. 2020 (see §1) | Symmetric bands with a Nyquist-gain polynomial. | Bands 17–31 bandwidths reduced for warping. Polynomial fit error is "±0.5 dB for the 31st band and less than ±0.2 dB for the other bands". | (see §1) | **Yes-full** |
| Liski & Välimäki DAFx-17 / Holters & Zölzer DAFx-06 (see §1) | Empirical fixes at the top bands. | Six top bandwidths hand-tuned **at 44.1 kHz**. ">1 dB … artifact of the bilinear transform" between the top octave bands at 48 kHz. | (see §1) | **Yes-full** |

**How large the bilinear-transform error is at 16 and 20 kHz (our computation, not from a paper)**

Setup: a constant-Q bell with the centre prewarped (RBJ/BLT style) and third-octave Q ≈ 2.15. Analog midpoint-gain edges sit at the neighbouring centres (±1/3 oct, so 0.667 oct wide). I mapped them through ω = 2·atan(Ω·tan(ω₀/2)).

| Centre | fs | Digital midpoint-gain edges | Width (oct) | Narrowing vs analog |
|---|---|---|---|---|
| 16 kHz | 44.1 kHz | 14.7–17.1 kHz | 0.22 | ≈ 3.0× |
| 16 kHz | 48 kHz | 14.4–17.4 kHz | 0.28 | ≈ 2.4× |
| 16 kHz | 96 kHz | 13.1–19.2 kHz | 0.55 | ≈ 1.2× |
| 16 kHz | 192 kHz | 12.8–19.9 kHz | 0.64 | ≈ 1.05× |
| 20.16 kHz | 44.1 kHz | 19.7–20.5 kHz | 0.06 | ≈ 10.7× |
| 20.16 kHz | 48 kHz | 19.2–20.9 kHz | 0.12 | ≈ 5.4× |
| 20.16 kHz | 96 kHz | 16.9–23.7 kHz | 0.49 | ≈ 1.4× |

The centre gain is exact, because prewarping fixes ω₀. The shape is what is wrong.

A +12 dB third-octave analog bell at 20.16 kHz still has **+10.1 dB at 22.05 kHz**, while every BLT bell has **0 dB** at Nyquist. For comparison, SGE3's band-31 Nyquist polynomial (Appendix A) gives ≈ +8.8 dB at a 12 dB filter gain **(our computation)**.

Vicanek's Orfanidis constraint, f₀ < (1 − 1/(2Q)) f_Ny ≈ 0.767 f_Ny, is **violated by the 20 kHz band at both 44.1 kHz (0.91) and 48 kHz (0.84)**.

**What this means for our plan**
- Bands 29–31 (12.7/16/20 kHz) at 44.1 and 48 kHz cannot be analog-accurate with one BLT biquad. ACGE and SGE do not fix the shape; they compensate through bandwidth tuning plus the LS solve, and **that tuning was done only at 44.1 kHz**.
- At 96 kHz and above the warping is small (≤ 1.4×). The per-rate interaction matrix still differs, so it must be recomputed per sample rate.
- Prewarping alone does not fix this (Darabundit & Abel).
- Options, in order:
  1. Rely on the ACGE/SGE solve with per-rate bandwidth tuning and verify with tests.
  2. Use Orfanidis/Vicanek-style Nyquist-gain or matched bells for the top bands.
  3. Oversample, which is expensive and adds latency.

---

## 3. Time-varying (recursive) filter parameter changes without artifacts

| Paper | Method | Reported numbers | Link (opened) | Verified? |
|---|---|---|---|---|
| Wishnick, "Time-Varying Filters for Musical Applications", *DAFx-14*, Erlangen | SVF discretised with a TDF-II trapezoidal integrator (equivalent to Zavalishin's TPT), with a **novel proof of time-varying BIBO stability**. Gives formulas mapping common EQ shapes, and any z-domain biquad, to the SVF. Compared DF2, coupled (GR), SVF, transient-minimised SVF (SVFR), stabilised SVF/TDF2 (SVFRC, TDF2RC), TDF2 and output switching (ZZ). | DC-step test: only SVF/SVFRC (and ZZ) are ideal. DF-II "exhibits a large transient followed by ripple". MUSHRA: 21 subjects, 100 Hz sine at 48 kHz, **single discontinuous change**. Table 5, trial 4 (peaking 100 Hz, Q 6, **gain −4→+4 dB**): DF2 43, SVF 43, **TDF2 95, TDF2RC 94**. Trial 5 (peaking Q change): SVF 25, TDF2 64. Text: SVF is "significantly worse when the peaking filter resonance or gain are changed". Output switching scored "bad" to "poor". Sideband energy vs MUSHRA **r = −0.59** (p = 7.02×10⁻⁵); transient variance vs MUSHRA r = 0.11 (n.s.). "Interpolating TDF-II coefficients can give less sensible intermediate transfer functions." | https://dafx.de/paper-archive/2014/dafx14_aaron_wishnick_time_varying_filters_for_.pdf ; code (BSD-3, data CC0) https://github.com/iZotope/time_varying_filters_paper | **Yes-full** |
| Laroche, "On the Stability of Time-Varying Recursive Filters", *JAES*, 2007 | State-space criteria based on the singular values of the state-transition matrix. In the 2nd-order case these estimate the max and average gain caused by coefficient changes. Compares topologies and stabilisation methods. | Abstract via search listing only. | (AES page 403) | **No** |
| Werner & McClellan, "Time-Varying Filter Stability and State Matrix Products", *DAFx-22* (DAFx20in22), Vienna, p. 101 | Extends Laroche's Criterion 1: the norm of the **product of state matrices over several steps** ≤ 1 is sufficient. Frozen coefficients are not required. | Eq. (1): BIBO stability ⟺ Σᵢ\|h[n,i]\| < G (the ℓ₁ norm of the time-varying impulse response). | https://dafx.de/paper-archive/2022/papers/DAFx20in22_paper_41.pdf | **Yes-full** (p. 1) |
| Zavalishin, *The Art of VA Filter Design*, rev. 2.1.2, 14 Feb 2020 | **TPT** (topology-preserving transform): trapezoidal integrators in the analog topology. | §3.11 (p. 81): a direct-form structure "will produce unsmoothed jumps in the output in response to jumps in the cutoff". TPT "explicitly aims at emulating the time-varying behavior of the analog prototype". "The direct forms suffer from precision loss issues … even 2nd-order direct forms could already noticeably suffer from precision losses." | https://www.discodsp.net/VAFilterDesign_2.1.2.pdf (mirror; NI URL 404) | **Yes-full** (§3.11) |
| Apple, `vDSP_biquadm_SetTargetsDouble[D]` reference, and the vDSP Programming Guide (archive), "Using Biquadratic Filter Functions" | Ramped coefficient targets for the multichannel cascade (macOS 13+). | `__interp_rate` must be in 0–1, else "behavior is undefined"; `__interp_threshold` > 0. Each `vDSP_biquadmD` call "increments the coefficients until the difference … is less than a specified threshold". The increment is "a function of" rate and target−initial. The guide says the coefficients are incremented "at each sample". Multichannel cascade: "implements a **direct-form 2** filter for each channel". Single-channel `vDSP_biquad`: "direct-form 1". **No stability statement.** | https://developer.apple.com/documentation/accelerate/vdsp_biquadm_settargetsdoubled.md ; https://developer.apple.com/library/archive/documentation/Performance/Conceptual/vDSP_Programming_Guide/UsingBiquadraticFilterFunctions/UsingBiquadraticFilterFunctions.html | **Yes-full** |

**What this means for our plan**
- Do **not** use vDSP_biquadm target-ramping. It interpolates raw coefficients in **Direct Form II**, which is the least robust time-varying structure in Wishnick and Zavalishin, and it carries no stability guarantee or shape guarantee. The docs also disagree on whether the ramp steps per sample or per call.
- An ACGE drag changes **all 31 filter gains** at once, because the LS solve couples them. Smooth in the parameter domain (command dB gains, or the solved filter dB gains) and recompute coefficients at a control rate.
- Wishnick found that for **peaking-gain changes**, TDF-II and stabilised TDF-II beat the SVF (95/94 vs 43). TDF-II with smoothed gains is therefore the evidence-backed default. Plain TDF-II is not provably stable when time-varying, so its stability must be verified by test.
- Wishnick's evidence also says that eliminating transients is the wrong goal for music; low sideband energy predicts quality (r = −0.59).

---

## 4. Peak and headroom after EQ

| Paper | Method | Reported numbers | Link (opened) | Verified? |
|---|---|---|---|---|
| Werner & McClellan, DAFx-22 (above) | BIBO bound. | Worst-case output peak / input peak = Σ\|h[n]\| (ℓ₁ norm), not max\|H(e^{jω})\|. | (see §3) | **Yes-full** |
| Balakrishnan & Boyd, "On Computing the Worst-Case Peak Gain of Linear Systems", *Systems & Control Letters* 19:265–269, 1992 | Bounds on the impulse-response ℓ₁ tail. | The ℓ∞ (peak-to-peak) gain is computable "to any desired accuracy". | https://web.stanford.edu/~boyd/papers/wc_ell_one.html | **Yes-abs** |
| Schlecht, Fierro, Välimäki & Backman, "Audio Peak Reduction Using a Synced Allpass Filter", *ICASSP 2022*, pp. 1006–1010 | A Schroeder **allpass** (\|H\| = 1) synced to autocorrelation peaks. | Peak reduction "spans from 0 to 5 dB depending on the input waveform". **Phase alone moves peak level by several dB.** | https://research.aalto.fi/fi/publications/audio-peak-reduction-using-a-synced-allpass-filter/ | **Yes-abs** |
| Robjohns, "Why do waveforms sometimes look lop-sided?", *Sound On Sound*, May 2013 | Practitioner explanation. | Asymmetry comes from harmonic phase relationships. A "phase rotator" changes the symmetry and therefore the peak level, without changing the magnitude. | https://www.soundonsound.com/sound-advice/q-why-do-waveforms-sometimes-look-lop-sided | **Yes-full** |
| ITU-R BS.1770-5 (11/2023), Annex 2 and Attachment 1 | True-peak meter: 4× oversampling at 48 kHz (to 192 kHz), 48-tap 4-phase FIR. "Incoming signals at higher sampling rates require proportionately less over-sampling (… 96 kHz … 2×)". | Max under-read 20·log(cos(π·f_norm/n)). **4×: 0.554 dB (f_norm 0.45), 0.688 dB (0.5)**; 8×: 0.136/0.169; 16×: 0.034/0.042; 32×: 0.008/0.010. Sample-peak meters: "3 dB under-read for an unfortunately-phased tone at a quarter of the sampling frequency"; transient under-reads "can commonly be several dBs". "Higher sampling rates and over-sampling ratios are preferred". | https://www.itu.int/dms_pubrec/itu-r/rec/bs/R-REC-BS.1770-5-202311-I!!PDF-E.pdf | **Yes-full** (pp. 18–21) |
| EBU R 128 (2014) | Loudness normalisation. | **"Maximum Permitted True Peak Level … shall be −1 dBTP"** (production). Target −23.0 LUFS, "±0.5 LU" tolerance. Distribution is deferred to Tech 3344. | https://tech.ebu.ch/docs/r/r128-2014.pdf | **Yes-full** |
| Nielsen & Lund, "0dBFS+ Levels in Digital Mastering", *AES 109th*, preprint 5251, 2000 | Intersample overs in consumer players. | Not opened (both hosts failed). | — | **No** |
| AES TD1008 (streaming loudness) | Codec-input true-peak recommendation. | Not opened. | — | **No** |

**Our derivation (standard result, not from the opened papers).** A first-order allpass (a + z⁻¹)/(1 + a z⁻¹) has \|H\| ≡ 1 but Σ\|h\| = 1 + 2\|a\|. Its worst-case peak gain therefore approaches 3× (+9.5 dB) as \|a\|→1. A cascade of minimum-phase bells with max\|H\| ≤ 0 dB can likewise raise sample and true peaks on real signals, typically by a few dB. ICASSP 2022 shows 0–5 dB from phase alone.

**What this means for our plan**
- The preamp −max(0, peak\|H\|) guarantees **steady-state sinusoidal gain ≤ 0 dB only**. It does **not** guarantee that sample peaks or true peaks will not rise.
- The answer to the question is "no": the guarantee needs ℓ₁, not ℓ∞.
- Keep the existing safety limiter **after** the EQ, with true-peak detection of ≥ 4× at 44.1/48 kHz (2× at 96 kHz), and a ceiling of about −1 dBTP (R 128 production value).
- Compute peak\|H\| on a **dense log grid** (between bands and up to Nyquist), not only at the 31 centres.
- Smooth the preamp itself, since it moves on every drag.

---

## 5. Level matching for fair A/B comparison (Compare)

| Paper | Method | Reported numbers | Link (opened) | Verified? |
|---|---|---|---|---|
| ITU-R BS.1116-3 (2015), "Methods for the subjective assessment of small impairments" | Listening-test standard. | Reference level **L_ref = 78 ± 0.25 dBA** per loudspeaker, set with pink noise. "The loudness of each excerpt needs to be adjusted subjectively by the group of skilled subjects". Headphones: level set for "a loudness equal to the reference sound field". It notes listeners may prefer different absolute levels. | https://www.itu.int/dms_pubrec/itu-r/rec/bs/R-REC-BS.1116-3-201502-I!!PDF-E.pdf | **Yes-full** (§6, §8.4) |
| ITU-R BS.1770-5, Annex 1 validation | K-weighted loudness (LKFS) vs subjective loudness. | r = 0.979 / 0.985 / 0.980 per dataset; "overall correlation of r = 0.977" over **336 sequences** (music, speech, etc.). | (BS.1770-5 PDF above, pp. 15–17) | **Yes-full** |
| EBU R 128 (2014) | Normalisation tolerance. | "±0.5 LU"; footnote: the tolerance "exists to allow for minor variations of meter calibrations and errors". | (above) | **Yes-full** |
| Kunchur, "The Human Auditory System and Audio", *Applied Acoustics* 211:109507, 2023 | Review with a JND table compiled from classic data. | "Level JNDs are on the order of 1 dB or less over most of the parameter space (SPL > 40 dB and f > 100 Hz), **dropping to 0.25–0.4 dB for SPL > 60 dB and f = 1000–4000 Hz**". "For broadband noise, JND ∼ 0.5–1 dB for SPL = 20–100 dB". Table 1 at 1 kHz: 0.41 dB at 60, 0.33 at 70, 0.29 at 80 dB SPL. At 4 kHz: 0.29 / 0.25 / 0.25. | https://arxiv.org/pdf/2307.00084 | **Yes-full** (pp. 7–8) |
| Jesteadt, Wier & Green, "Intensity discrimination as a function of frequency and sensation level", *JASA* 61:169–177, 1977 | Classic pure-tone level DL data. | Citation verified only; values not opened. | https://www.fon.hum.uva.nl/praat/manual/Jesteadt__Wier___Green__1977_.html | **Partial** |
| Toole & Olive, "Hearing is believing vs. believing is hearing", *AES 97th*, preprint 3894, 1994 | Blind vs sighted loudspeaker tests. | A forum quote says "equal loudness within 0.5 dB using B-weighted pink noise". Not confirmed. | (AES 403) | **No** |
| Berendes, Travaglini & Uhle, "Validating Loudness Alignment via Subjective Preference…", *AES 153rd*, 2022 | Listener loudness adjustment vs BS.1770-4. | Search-index abstract: BS.1770-4 and listener gains "differ on average by 2.2 dB"; listener-derived gains improved alignment MOS by 16% of the scale. Not confirmed. | (Fraunhofer and AES pages blocked) | **No** |
| Lavandier et al., "Influence of level setting on loudspeaker preference ratings" (HAL) | Level setting changes preference outcomes. | HAL page blocked (bot wall). | — | **No** |

**What this means for our plan**
- The level JND for music at normal listening levels is about 0.25–1 dB, depending on frequency and level (Kunchur). Calibration practice holds tolerances of ±0.25 dB (BS.1116-3).
- So Compare should match the A and B paths to **≤ 0.1–0.2 dB computed loudness**, using BS.1770 K-weighted loudness over the same audio window (r ≈ 0.98 across programmes).
- Match by **attenuating the louder path**, never by boosting into the limiter. Keep the limiter, preamp and ramps identical across A and B.
- Disclose to users that meter-based matching is imperfect when the spectral difference between A and B is large.

---

## 6. Tone-control macro design (5 macros → 31 band gains)

| Paper | Method | Reported numbers | Link (opened) | Verified? |
|---|---|---|---|---|
| Baxandall, "Negative-Feedback Tone Control", *Wireless World*, Oct 1952, pp. 402–405 | Two pots give independent bass and treble lift and cut without switches. | "A level response is obtained with both potentiometers at mid-setting". "Treble-response curves are of almost constant shape, being shifted along the frequency axis". | https://effectrode.com/wp-content/uploads/2018/09/negative_feedback_tone_baxandall.pdf | **Yes-full** (p. 1) |
| Välimäki & Reiss 2016 (§3.1–3.2) | Shelf design with **midpoint gain √G**, which is the arithmetic mean in dB. | "A cascade of a low and high shelf with the same crossover frequency ω_c and gain G will produce a constant gain G across all frequencies" (Fig. 2). This is the basis for a tilt control and for complementary weights. | (see §1) | **Yes-full** |
| McGrath, Baird & Jackson, "Raised Cosine Equalization Utilizing Log Scale Filter Synthesis", *AES 117th Conv.*, 2004 | Raised-cosine shapes **on log₂ frequency**: Gain(f) = Boost·[0.5 + 0.5·cos(π(f − F_c − W/2)/W)] across a transition W octaves wide. Minimum-phase realisation. | "Neighboring filters can be configured to sum to a flat frequency response". Matching one raised-cosine filter takes "a filter bank of 7 traditional parametric filters". Synthesis uses a "constant 1/24th octave filter bank". | https://twaudio.de/wp-content/-pdf_files/TW_AUDiO_White_Papers_McGrath_et_al-Raised_Cosine_Equalization_EN.pdf | **Yes-full** (pp. 1–5) |
| Schultz, Hahn & Spors, "Shelving filter cascade with adjustable transition slope and bandwidth", *AES 148th*, paper 10339, 2020 | Biquad shelf cascade in which two of level, slope and bandwidth are set freely. | Too few biquads per octave cause "deviations in level and bandwidth as well as a rippled slope". | https://research.chalmers.se/en/publication/519520 | **Yes-abs** |
| Cartwright & Pardo, "Social-EQ: Crowdsourcing an Equalization Descriptor Map", *ISMIR 2013* | Learns a 40-band (ERB-spaced) EQ curve per descriptor word by regressing ratings on band gains. | "324 distinct words in 731 learning sessions". Descriptor meaning varies between users ("Bob's 'warm' ≠ Sarah's 'warm'"). | https://archives.ismir.net/ismir2013/paper/000173.pdf | **Yes-full** (pp. 1–2) |
| Stables et al., "SAFE…", *ISMIR 2014* (demo) | Crowdsourced descriptor-to-EQ data captured inside a DAW (SAFE-DB). | Search only. | — | **No** |
| Holters & Zölzer, "Parametric Higher-Order Shelving Filters", *EUSIPCO 2006* | Arbitrary-order shelves. | Not opened. | — | **No** |

**Bands named Bass/Body/Mids/Presence/Air.** I found no verified paper that fixes these exact boundaries. They are an engineering convention. SocialEQ and SAFE show that descriptor-to-band mappings are learned and differ between people, so treat 150/500/2k/6k Hz as a design choice and validate it by ear.

**What this means for our plan**
- Build the five macro weights as a **raised-cosine partition of unity on log₂ f**. Use rising shelves S_k with centres at 150, 500, 2k and 6k Hz and width W ≈ 1 oct. The weights are w_Bass = 1 − S₁, w_Body = S₁ − S₂, …, w_Air = S₄, and they sum to exactly 1 (telescoping sum), so all five macros at +x give flat +x, which is the Baxandall "level at mid" property.
- Feed the macro sum into the 31 command gains, not into extra filters, so the macros stay inside the accurate GEQ.
- **Clamp the final command gains to ±12 dB**, the validated ACGE/SGE range; multi-shelf notes peak GEQs are "limited to 24 dB" span. The graph must show the clamped, played result.

---

## 7. Preference and target-curve literature (for preset re-voicing)

| Paper | Method | Reported numbers | Link (opened) | Verified? |
|---|---|---|---|---|
| Olive, "The Perception and Measurement of Headphone Sound Quality: What Do Listeners Prefer?", *Acoustics Today* 18(1):58ff, Spring 2022 | Review of Harman's headphone research: virtual-headphone blind tests and a linear preference model. | Harman target preferred by **64%** of listeners. **15%** prefer it "with 4–6 dB more bass"; **21%** "with 2 dB less bass". Model: "correlation between the predicted and measured ratings is 0.86, with an error of 6.7 ratings on a 100-point scale"; IE model r = 0.91. Virtual-vs-real headphone ratings correlate "0.86 to 0.99". "Adding too much bass beyond the Harman target may alienate many listeners." | https://acousticstoday.org/issues/2022AT/Spring2022/files/basic-html/page58.html (and pp. 61, 63, 65) | **Yes-full** (pages listed) |
| Olive, Welti & Khonsaripour, "A Statistical Model that Predicts Listeners' Preference Ratings of Around-Ear and On-Ear Headphones", *AES 144th*, paper 9919, 2018 | 31 headphones, 130 listeners. | Search-index abstract only. | (AES 403) | **No** |
| Olive, Welti & McMullin, "Listener Preferences for In-Room Loudspeaker and Headphone Target Responses", *AES*, paper 8994, 2013 | Listeners adjusted bass and treble. | Search abstract: preferred loudspeaker target had "2 dB more bass and treble" than the headphone target; large individual spread. | (AES 403) | **No** |

**What this means for our plan**
- Re-voice presets as **smooth, low-order shapes** (shelves and tilts via the Tone macros), not jagged per-band patterns.
- Size the Bass macro to cover the measured preference spread (−2 to +6 dB re target). ±6 dB suffices.
- Presets cannot assume a target, because we do not know the user's headphone or speaker. Keep them modest and loudness-matched in Compare (§5).

---

## Risks or corrections to our plan

1. **Sample-rate tuning gap (correction).** ACGE3's c = 0.4, g_p = 17 dB and the six hand-tuned top bandwidths, and SGE3's Nyquist polynomials, were all tuned **only at 44.1 kHz**. Warping differs a lot at 48 kHz (top band 5.4× vs 10.7× too narrow), so the 44.1 kHz values may not transfer. Rebuild the interaction matrix per rate. Re-tune the top bandwidths per rate (44.1/48/88.2/96/176.4/192). Gate each rate with the published tests: zigzag ±12 dB, the third-octave hard case, and ≥10,000 random settings with max error ≤ 1 dB.
2. **Pick the band formula last.** SGE3 (0.81 dB) beats ACGE3 (0.97 dB) on the identical test with the same filter count. Implement ACGE3 first (open reference to cross-check), make the band-filter formula pluggable, and evaluate SGE3 against the same gate.
3. **"Accurate" is narrower than it sounds.** The < 1 dB claim covers command points, and midpoints only when neighbours are equal. Ripple between unequal neighbours is unbounded by the method. The honest graph must evaluate |H| on a dense log grid (≥ 1/24 oct) up to Nyquist.
4. **Top-band physics (20 kHz at 44.1/48 kHz).** The 20 kHz band violates the Orfanidis prescribed-Nyquist constraint (f₀ < 0.767 f_Ny for Q ≈ 2.15). A BLT bell is pinned to 0 dB at Nyquist, while the analog bell would be +10 dB. Accept and disclose this, with the graph showing the truth, or use a matched or oversampled top section.
5. **Headroom is not peak safety (correction).** −max(0, peak|H|) bounds only steady-state gain. Phase can raise sample and true peaks; the bound is ℓ₁ = Σ|h| > max|H|, and ICASSP 2022 measured 0–5 dB from allpass phase alone. Keep a true-peak limiter after the EQ (≥ 4× oversampled detection at 44.1/48 kHz; BS.1770-5 4× still under-reads up to 0.55–0.69 dB). Smooth the preamp.
6. **Do not use vDSP_biquadm ramping (correction).** It is DF-II with interpolated coefficients and no stability guarantee. Smooth the gains, recompute coefficients at a control rate (off the audio thread), and publish them via the existing wait-free triple buffer. Prefer TDF-II, which won the gain-change trial in Wishnick, over assuming an SVF is best. Test with fast drags and preset jumps, and measure sideband energy rather than transient variance.
7. **Numerical precision at high fs and low f.** The 19.69 Hz band at 192 kHz has poles near z = 1. Zavalishin warns that direct forms "noticeably suffer from precision losses", and Vicanek's matched formulas "require double precision". Use double-precision coefficients and state (or TDF-II/SVF), and test a 20 Hz ±12 dB band at 192 kHz for noise and DC drift.
8. **Compare matching tolerance.** The JND is about 0.25–0.4 dB at 1–4 kHz above 60 dB SPL, so match A/B to ≤ 0.1–0.2 dB by K-weighted loudness, attenuating the louder side. Meter-vs-listener disagreements of a few dB per item are reported (Berendes 2022, **unverified**), so do not market Compare as perceptually perfect.
9. **Macros plus manual edits can exceed ±12 dB.** Sum first, then clamp per band, and render the clamped result. This avoids repeating the old "sum-of-dB clamp" bug that hid the truth.
10. **Licensing.** acge3.m has no license and Bank's parfilt is non-commercial only. Implement from the equations in the papers (all formulas needed are in SPL-17, DAFx-17 and Applied Sciences 2020, which is CC BY).

---

## Appendix A — Equations transcribed from the verified sources

**A1. ACGE band filter (Välimäki & Liski 2017, Eqs. 6–7; Orfanidis peak/notch with unity DC gain).**

```
H(z) = [ (1 + Gβ) − 2cos(ω_c) z⁻¹ + (1 − Gβ) z⁻² ] / [ (1 + β) − 2cos(ω_c) z⁻¹ + (1 − β) z⁻² ]
β    = tan(B/2)                                   if G = 1
β    = sqrt( |G_B² − 1| / |G² − G_B²| ) · tan(B/2)   otherwise
```

- G is the linear peak gain, ω_c = 2πf_c/f_s, B = 2πf_B/f_s, and G_B is the gain at the band edge.
- ACGE sets g_B = c·g in dB, with c = 0.3 for octave and c = 0.4 for third-octave.

**A2. ACGE solve (Välimäki & Liski 2017, Eqs. 8–10; DAFx-17 Eq. 3).**

1. Choose 2M − 1 design frequencies: the M centres plus the geometric-mean midpoints. For third-octave that is 61.
2. Build the target t₁: command dB gains in the odd rows and the linear interpolation of neighbours in the even rows.
3. Build B (61×31). Element B[k,m] is the dB magnitude of band filter m, designed at prototype gain g_p (17 dB), evaluated at design frequency k and divided by g_p. B can be precomputed per sample rate.
4. Solve g = B⁺t₁ = (BᵀB)⁻¹Bᵀt₁.
5. Iterate once. Rebuild B₁ with each filter designed at its own solved gain g_m, normalised by g_m (handle g_m ≈ 0 as in the reference code), then solve g₁ = B₁⁺t₁.
6. Design the 31 filters from g₁.

SGE3 variant: weighted LS, g = (BᵀWB)⁻¹BᵀWt₁ (Rämö 2020, Eq. 3), with g_p = 11 dB and c = 0.38.

**A3. SGE3 Nyquist-gain polynomial (Rämö 2020, Eq. 16, Table 2).**

g_Nq,m = q₁·g_m + q₃·g_m³ (dB). q₀ = q₂ = 0. Bands 1–22 use ≈ 0 dB.

| Band m (f_c) | q₁ | q₃ |
|---|---|---|
| 23 (3175 Hz) | 0.00166 | 8.09×10⁻⁶ |
| 24 (4000 Hz) | 0.00295 | 1.25×10⁻⁵ |
| 25 (5040 Hz) | 0.00544 | 1.91×10⁻⁵ |
| 26 (6350 Hz) | 0.0105 | 2.84×10⁻⁵ |
| 27 (8000 Hz) | 0.0214 | 4.08×10⁻⁵ |
| 28 (10080 Hz) | 0.0456 | 5.46×10⁻⁵ |
| 29 (12700 Hz) | 0.103 | 6.27×10⁻⁵ |
| 30 (16000 Hz) | 0.257 | 3.68×10⁻⁵ |
| 31 (20160 Hz) | 0.754 | −1.18×10⁻⁴ |

These were fitted at **f_s = 44.1 kHz only**. The full SGE3 coefficient formulas are Rämö 2020 Eqs. 9–15 (CC BY paper); transcribe from the PDF, not from this note.

**A4. True-peak under-read (BS.1770-5, Annex 2, Attachment 1).** Max under-read (dB) = 20·log₁₀(cos(π·f_norm/n)), where n is the oversampling ratio and f_norm = f_max/f_s.

**A5. Raised-cosine log-frequency shelf (McGrath et al. 2004).** With f in octaves (log₂):

```
Gain(f) = 0                                                   for f ≤ F_c − W/2
Gain(f) = Boost · [0.5 + 0.5·cos(π (f − F_c − W/2) / W)]      for F_c − W/2 < f < F_c + W/2
Gain(f) = Boost                                               for f ≥ F_c + W/2
```

Taking S_k as this curve with Boost = 1 at each macro crossover, the differences S_k − S_{k+1} form a partition of unity (§6).

**A6. Shelf midpoint convention (Välimäki & Reiss 2016, Eq. 3).** |H(e^{jω_c})| = √G at the crossover, and H_HS(z) = G / H_LS(z). So the complementary low and high shelves cascade to a constant G.

---

## Appendix B — Test gate implied by the literature

- **Error metric (DAFx-17 §3.1; Rämö 2020 §5):** the max |command − response| in dB at the 31 centres. Where adjacent commands are equal, also measure the plateau between them; DAFx-17 used 16 points between neighbours. Pass: ≤ 1 dB, the "hi-fi" tolerance cited by DAFx-17 and Rämö 2020.
- **Test settings:**
  - all +12 dB and all −12 dB;
  - zigzag ±12 dB;
  - the DAFx-17 §5.1 "hard case" vector (copy it from the paper, Fig. 12c/d);
  - every-third-down (SPL-17);
  - ≥ 10,000 random settings, half extreme {0, ±12} and half random integers in [−12, 12] (Rämö 2020).
- **Run the gate at every supported f_s** (44.1, 48, 88.2, 96, 176.4, 192 kHz). The published tuning covers 44.1 kHz only.
- **Honest graph:** compare the plotted curve with an offline FFT of the cascade's impulse response on a ≥ 1/24-oct grid. They should match to within plotting resolution.
- **Time-variation (Wishnick §6):**
  - fast drag sweeps and preset jumps on a 100 Hz sine and on music;
  - measure the sideband RMS around each change (85 ms Hann window, excluding the signal's ERB);
  - include a DC-step test for state blow-up;
  - include TSan/RT-safety, already standard in this repo.
- **Peaks:** on a music corpus, log the sample-peak and true-peak change (EQ in vs out at equal preamp); confirm the limiter catches the residual. Include the worst-case allpass-like settings (steep adjacent ±12 dB).
- **Compare:** the loudness difference between A and B must be ≤ 0.1 dB by BS.1770 integrated loudness over the comparison window, with no limiter activity introduced by matching.

---

## Appendix C — Items I could not verify this session

- **Oliver & Jot 2015, primary:** only via SPL-17 Table I and MathWorks.
- **Rämö, Välimäki & Bank 2014 PGE, primary:** only via SPL-17, DAFx-17 and the review.
- **Bank SPL 2008:** abstract via search only.
- **Abel & Berners ICMC 2004:** PDF returned 403; CCRMA abstract only.
- **Orfanidis JAES 1997:** via Vicanek's reproduction only.
- **Massberg AES 2011:** via Vicanek's reproduction only.
- **Clark et al. JAES 2000:** not obtained.
- **Darabundit, Abel & Berners NBT, JAES 2022:** not obtained.
- **Laroche JAES 2007:** abstract via search only.
- **Nielsen & Lund AES 2000:** not obtained.
- **AES TD1008:** not obtained.
- **Toole & Olive 1994:** not obtained.
- **Berendes et al. AES 2022:** not obtained.
- **Lavandier et al. (HAL):** not obtained.
- **Stereophile level-matching sidebar:** not obtained.
- **SAFE (ISMIR 2014):** not obtained.
- **Holters & Zölzer EUSIPCO 2006:** not obtained.
- **Olive et al. AES 2018 and AES 2013:** not obtained.
- **Jesteadt et al. 1977:** citation only.
- **Code repositories not opened:** the Rämö 2020 MATLAB scripts, the all-about-audio-EQ code, and the MultiShelfGEQ GitHub repository.
