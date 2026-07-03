import Testing

// Auto-advance state machine tests have been split into themed files:
//   MockAdvanceController.swift           — MockAdvanceController mirror + makeTracks/makeURL helpers
//   AutoAdvanceLinearRepeatShuffleTests.swift — VM-AA-01..12 (linear, repeat, shuffle, error path)
//   AutoAdvanceGaplessSeamTests.swift     — VM-AA-14..19 (seam correctness, position, duration)
//   AutoAdvanceReconfigureGapTests.swift  — VM-AA-RGAP-1, VM-AA-RTR-1 (reconfigure-gap, regression)
//   AutoAdvanceDeviceLossTests.swift      — VM-AA-06..07, VM-AA-13, VM-AA-18 (device-loss, playlist mutation)
