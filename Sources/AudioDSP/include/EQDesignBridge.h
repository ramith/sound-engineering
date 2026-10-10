#pragma once

//
// EQDesignBridge.h — Pure C header: the 31-band graphic-EQ designer (Sprint EQ, EQ1a), for Swift.
//
// Exposes the C++ GraphicEQDesigner (EQ/GraphicEQDesigner.h) behind an opaque, owner-local handle:
// each owner creates its own designer, so no designer's per-sample-rate tables are ever shared
// between threads. The UI uses it to draw the curve the engine actually plays; the engine's
// Realizer holds its own C++ instance directly.
//
// Must stay valid ISO C11 (no C++ namespaces, no <cstdint>, no class declarations): it is
// re-exported through DeviceBridge.h, the single Swift bridging header. Fixed-size data travels as
// (pointer, count) pairs in caller-owned buffers, keeping every struct POD (as PureModeBridge.h).
//
// Thread-safety: a designer is NOT thread-safe; use one per thread or serial queue. Every call is
// off the real-time thread. asEqDesign allocates nothing and takes no locks.
//

#include "CApiNoexcept.h"
#include <stdbool.h>
#include <stdint.h>

/// An opaque graphic-EQ designer. Create with asEqDesignerCreate(); destroy with
/// asEqDesignerDestroy().
typedef struct AsEqDesigner AsEqDesigner;

/// Where one design's results go. Every buffer is caller-owned; asEqDesign writes them only when
/// it returns true.
typedef struct
{
    /// The played dB at the 31 band centres 10^(1.3 + 0.1·m) Hz. `pointCount` (31) floats.
    /// Required.
    float* centreDb;
    /// The frequencies (Hz) to evaluate the played response at; each must be finite and in
    /// [0, sampleRate / 2). `responseCount` doubles. May be NULL only when responseCount is 0.
    const double* responseHz;
    /// Receives the played dB at each of `responseHz`. `responseCount` floats.
    float* responseDb;
    /// The length of responseHz and responseDb (the UI's fixed grid is 256 points).
    uint32_t responseCount;
    /// Optional (NULL = not wanted), `pointCount` (31) doubles each: the solved per-band bell
    /// gains (dB) and the finished SVF coefficients the engine runs for them.
    double* filterGainDb;
    double* svfK;
    double* svfM1;
} AsEqDesignOutput;

#ifdef __cplusplus
extern "C"
{
#endif

    /// Create a designer (~47 KB, heap). Returns NULL on allocation failure.
    AsEqDesigner* asEqDesignerCreate(void) AUDIODSP_C_NOEXCEPT;

    /// Destroy a designer from asEqDesignerCreate(). NULL-safe.
    void asEqDesignerDestroy(AsEqDesigner* designer) AUDIODSP_C_NOEXCEPT;

    /// Design the cascade that plays `pointsDb` at `sampleRate`, and read back what it plays.
    ///
    /// @param designer    From asEqDesignerCreate(); its per-rate tables are reused across calls.
    /// @param pointsDb    `pointCount` target points (dB), one per band. Points beyond ±12 dB are
    ///                    clamped to ±12 dB.
    /// @param pointCount  Must be exactly 31.
    /// @param sampleRate  The design rate (Hz); must be finite and within [44 kHz, 768 kHz].
    /// @param output      Where the results go (see AsEqDesignOutput).
    /// @return true when designed and written. false — writing nothing — on a NULL designer,
    ///         points, output or centreDb; a pointCount other than 31; a non-finite point; a rate
    ///         outside the domain; a NULL response buffer with a non-zero responseCount; a response
    ///         frequency outside [0, sampleRate / 2); or a solve that fails to stay finite.
    bool asEqDesign(AsEqDesigner* designer,
                    const float* pointsDb,
                    uint32_t pointCount,
                    double sampleRate,
                    const AsEqDesignOutput* output) AUDIODSP_C_NOEXCEPT;

#ifdef __cplusplus
} // extern "C"
#endif
