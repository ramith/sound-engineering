#pragma once

// AUDIODSP_C_NOEXCEPT — a noexcept-specifier for the extern "C" bridge functions under C++.
//
// A C++ exception must never unwind across the C ABI into Swift — that is UB / std::terminate.
// (The AudioDSP target is built -fno-exceptions, so nothing throws today; this documents and
// enforces the contract uniformly across ALL bridge headers, and stays correct if that flag is
// ever relaxed.) Expands to `noexcept` for C++ and to nothing for the C compiler Swift's bridging
// uses, where `noexcept` is not a keyword.
//
// Single definition (Stage-2 review IDM-3): this replaces the copies previously inlined in
// MetadataBridge.h and PureModeBridge.h. Pure C — safe for every Swift-bridged includer.
#ifndef AUDIODSP_C_NOEXCEPT
#ifdef __cplusplus
#define AUDIODSP_C_NOEXCEPT noexcept
#else
#define AUDIODSP_C_NOEXCEPT
#endif
#endif
