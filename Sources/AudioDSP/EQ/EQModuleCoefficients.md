# EQ Module Coefficients

## Overview

`EQModuleCoefficients.h` implements the coefficient calculation and validation for the 31-band parametric EQ module. It maps user-facing gains (in dB) to a cascade of up to 10 biquad filter coefficients, suitable for real-time processing via `vDSP_biquad()`.

## Key Design Decisions

### 1. Greedy Region Fitting

This implementation uses a **simplified fitting algorithm**:
- Groups consecutive frequency bands with significant gains (≥ 0.5 dB threshold)
- Creates peaking filters at the center frequency of each region
- Limits cascade to 10 biquads maximum

The shipped design is "static but correct" — coefficients are pre-computed off-RT and validated. A dynamic ML-based fitting optimizer is a possible future enhancement.

### 2. Minimum-Phase by Default

All filters are **minimum-phase** (poles and zeros designed for causal response):
- Validates pole stability: `|a2| < 1` and `|a1| ≤ 1 + a2` (Schur-Cohn conditions)
- No linear-phase option (a possible future enhancement)
- Group delay inherently non-negative for minimum-phase filters

### 3. RBJ Peaking Filter Design

Coefficients computed using the **Audio EQ Cookbook** formulas:
```
Peaking EQ filter (bell curve):
  H(z) = (b0 + b1*z^-1 + b2*z^-2) / (1 + a1*z^-1 + a2*z^-2)

where:
  A = 10^(dB_gain / 40)
  w0 = 2π * f_center / f_sample
  Q = adaptive based on gain magnitude
  α = sin(w0) / (2Q)

  b0 = 1 + α*A
  b1 = -2*cos(w0)
  b2 = 1 - α*A
  a0 = 1 + α/A
  a1 = -2*cos(w0)
  a2 = 1 - α/A
```

Coefficients normalized by `a0` for standard form.

## API

### `EQParams computeBiquadCascade(const std::array<float, 31>& gains, float sampleRate)`

**Input:**
- `gains`: Array of 31 band gains in dB. Typical range: ±12 dB per band (enforced).
- `sampleRate`: Sample rate in Hz (e.g., 48000, 96000).

**Output:**
- `EQParams` struct containing:
  - `biquads[10]`: Cascaded biquad coefficients (b0, b1, b2, a1, a2)
  - `numBiquads`: Number of active biquads (1–10)
  - `masterGainLinear`: Overall gain (always 1.0)

**Behavior:**
- **All gains = 0 dB**: Returns unity-gain pass-through (1 biquad: `[1, 0, 0, 0, 0]`)
- **Single peak**: Creates peaking filter at peak frequency
- **Multiple peaks**: Groups by gain region, creates cascaded peaking filters
- **Extreme gains**: Clamped to ±12 dB before processing
- **All gains < 0.5 dB**: Treated as pass-through

## Example Usage

```cpp
#include "EQ/EQModuleCoefficients.h"
using namespace AdaptiveSound;

// User selects "Presence" preset: boost mid-high frequencies
std::array<float, 31> gains{};
gains[18] = 3.0f;  // 1.25 kHz: +3 dB
gains[20] = 4.0f;  // 2 kHz: +4 dB
gains[22] = 3.0f;  // 3.15 kHz: +3 dB

// Compute coefficients off-RT
EQParams eqParams = EQModuleCoefficients::computeBiquadCascade(gains, 48000.0f);

// Publish to DSPKernel for real-time processing
kernel->publishTargetState(targetState);
```

## Validation

### Stability Checks
- Poles inside unit circle (verified in `validateMinimumPhase()`)
- Schur-Cohn inequality: `|a1| ≤ 1 + a2`
- No NaN/Inf coefficients

### Minimum-Phase Verification
- Group delay always non-negative (inherent to minimum-phase design)
- No explicit group delay computation (a possible future enhancement for spectral analysis)

## 31-Band Center Frequencies (ISO 3-Octave)

```
Index  Hz        Index  Hz        Index  Hz
  0    20         11   250         22   3150
  1    25         12   315         23   4000
  2    31.5       13   400         24   5000
  3    40         14   500         25   6300
  4    50         15   630         26   8000
  5    63         16   800         27  10000
  6    80         17  1000         28  12500
  7   100         18  1250         29  16000
  8   125         19  1600         30  20000
  9   160         20  2000
 10   200         21  2500
```

## Edge Cases

1. **Nyquist Frequency**: Frequencies ≥ `sampleRate/2` are clamped to safe values (20–20 kHz).
2. **Very Small Gains**: Gains < 0.5 dB are ignored (treated as zero).
3. **Extreme Gains**: ±12 dB limits enforced; values outside clamped silently.
4. **Empty Result**: If all bands have zero or near-zero gain, returns unity pass-through.

## Testing

All test cases in `Tests/EQModuleCoefficientsTests.cpp`:
- ✅ Flat response (0 dB → pass-through)
- ✅ Single-band peak (frequency response shape)
- ✅ Extreme gains (±12 dB stability)
- ✅ Pole stability (Schur-Cohn conditions)
- ✅ Multiple peaks (complex responses)
- ✅ Small gains (below threshold)
- ✅ Different sample rates (44.1k, 48k, 96k)
- ✅ Biquad count limits (max 10)
- ✅ Deterministic output (consistency)
- ✅ Extreme band indices (20 Hz, 20 kHz)

## Performance

- **Off-RT computation**: No real-time constraints; ~1 ms on modern CPU for 31-band fitting
- **Memory**: Negligible (local arrays only, no allocations)
- **No SIMD**: Single-threaded scalar math (C++17, no Accelerate for coefficient generation)

## Future Enhancements

1. **ML-Based Fitting**: Dynamic fitting for optimal spectral response
2. **Linear-Phase Option**: Zero-phase filtering for professional mastering
3. **Group Delay Analysis**: Spectral visualization of phase response
4. **Preset Morphing**: Smooth interpolation between presets
5. **Adaptive Q**: Automatic bandwidth adjustment based on neighboring gains

## References

- Audio EQ Cookbook (RBJ): https://www.w3.org/TR/audio-eq-cookbook/
- Minimum-phase filter design: Oppenheim & Schafer, *Discrete-Time Signal Processing*
- Biquad coefficient stability: Schur-Cohn stability criterion
