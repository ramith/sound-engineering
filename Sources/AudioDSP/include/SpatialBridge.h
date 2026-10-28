#pragma once

//
// SpatialBridge.h — Pure C header: the stereo fold's surface for Swift (R1.1-B, the level-and-fold
// design, docs/design/level-and-fold/README.md, §S2 and §9).
//
// Empty at the coordinator's commit 0 of W4: lane 2 owns this file and fills it with the fold's
// C-ABI (the spatial unit's parameters, the backstop's gain-reduction read-out, S2's crossfeed-
// bypass signal). It exists now so the include below and the module's surface are settled before
// the lanes start, and neither lane edits DeviceBridge.h.
//
// Must stay valid ISO C11 (no C++ namespaces, no <cstdint>, no class declarations): it is
// re-exported through DeviceBridge.h, the module's single Swift-visible header.
//
