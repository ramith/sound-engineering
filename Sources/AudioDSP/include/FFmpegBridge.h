#pragma once

//
// FFmpegBridge.h — Pure C header for Swift: the "Use FFmpeg for other formats" switch (R1.1-A,
// founder decision FD-3, council C-99).
//
// FFmpeg is an opt-in, off by default: while it is off it is never loaded, and the decode
// fallback and the metadata scan use Apple's decoder only. The app sets the switch from the
// listener's setting (`SettingsKit.ListeningSettings.useFFmpeg`) before any library work, and
// reads back how the load went for the Settings line. Both calls are an atomic read or write —
// no load, no I/O — so any thread may make them. The load itself happens the first time a file
// needs FFmpeg, on that file's (background) thread. Implemented in FFmpegLoader.cpp.
//
// MUST be valid ISO C11 (it is re-exported by DeviceBridge.h, the single Swift-visible module
// header): the state is a uint8_t code in a documented order, the bridge's convention
// (PureModeBridge.h). #pragma once guards the double-include.
//

#include "CApiNoexcept.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// Turn FFmpeg on (non-zero) or off (0). Off at process start.
    void ffmpegSetEnabled(int enabled) AUDIODSP_C_NOEXCEPT;

    /// 1 while FFmpeg is on, else 0.
    int ffmpegIsEnabled(void) AUDIODSP_C_NOEXCEPT;

    /// Where FFmpeg stands now (never loads anything to answer). Codes, in this order (Swift
    /// `FFmpegOptIn.State`):
    ///   0 off           — the setting is off: FFmpeg is never loaded or used;
    ///   1 standby       — on; it loads the first time a file needs it;
    ///   2 loaded        — on, and loaded from a trusted fixed path at the right majors;
    ///   3 not found     — on, but no FFmpeg is installed at the fixed paths;
    ///   4 refused       — on, but a library file or its folder can be changed by another user;
    ///   5 wrong version — on, but the installed FFmpeg is not the version this build uses.
    uint8_t ffmpegState(void) AUDIODSP_C_NOEXCEPT;

#ifdef __cplusplus
} // extern "C"
#endif
