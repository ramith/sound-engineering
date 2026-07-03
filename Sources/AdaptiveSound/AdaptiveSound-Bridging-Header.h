//
// AdaptiveSound-Bridging-Header.h
// Pure-C interface exposed to Swift.
//
// Only pure-C headers may be listed here (no C++ namespaces, no <cstdint>,
// no class declarations).  DeviceBridge.h is the sole interface Swift needs:
// it declares CDeviceInfo and the device enumeration/selection functions.
//

#ifndef ADAPTIVESOUND_BRIDGING_HEADER_H
#define ADAPTIVESOUND_BRIDGING_HEADER_H

#include "../AudioDSP/include/DeviceBridge.h"
#include "../AudioDSP/include/PureModeBridge.h"

#endif // ADAPTIVESOUND_BRIDGING_HEADER_H
