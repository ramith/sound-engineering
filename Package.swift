// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AdaptiveSound",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
    ],
    targets: [
        .executableTarget(
            name: "AdaptiveSound",
            dependencies: ["AudioDSP", "AudioFormatKit", "LibraryStore"],
            path: "Sources/AdaptiveSound",
            // Info.plist is consumed by scripts/bundle-app.py, not by SwiftPM.
            exclude: ["Info.plist"],
            resources: [
                .process("Assets.xcassets"),
            ],
            swiftSettings: [
                .unsafeFlags(["-suppress-warnings"], .when(configuration: .debug)),
                // Explicitly import DeviceBridge.h as the Obj-C bridging header.
                // The auto-discovered bridging header (AdaptiveSound-Bridging-Header.h)
                // is not reliably processed by SPM for executable targets; the explicit
                // flag guarantees CDeviceInfo, enumerateOutputDevicesC, and
                // selectOutputDeviceC are visible to Swift source files.
                .unsafeFlags([
                    "-import-objc-header",
                    "Sources/AudioDSP/include/DeviceBridge.h",
                ]),
            ]
        ),
        // Headless M1 acceptance gate: proves the custom v3 AU registers, instantiates, sits
        // in the AVAudioEngine graph, and renders. `swift run VerifyAUGraph`. (swift test is
        // broken here; this is the runnable integration check for the AU-graph path.)
        .executableTarget(
            name: "VerifyAUGraph",
            dependencies: ["AudioDSP", "AudioFormatKit"],
            path: "Sources/VerifyAUGraph",
            swiftSettings: [
                .unsafeFlags([
                    "-import-objc-header",
                    "Sources/AudioDSP/include/DeviceBridge.h",
                ]),
            ]
        ),
        // Persistent library store (Sprint 8, S8.1a). System SQLite ONLY (import SQLite3;
        // .linkedLibrary("sqlite3")) — ZERO external SwiftPM deps, matching the CoreAudio/
        // Accelerate system-lib idiom and avoiding the toolchain-skew class that broke
        // `swift test`. Its own library target so BOTH the app (AdaptiveSound) and the offline
        // gate (VerifyLibraryStore) link the identical store/schema/migration implementation —
        // no drift. Off the audio path entirely (additive; S8.1 touches no DSP).
        .target(
            name: "LibraryStore",
            dependencies: [],
            path: "Sources/LibraryStore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        // Headless S8.1a acceptance gate: proves the store opens/creates/migrates, the v1 schema
        // is correct, the migration runner is transactional + downgrade-guarded, corruption is
        // quarantined (with -wal/-shm sidecars) + rebuilt, and data survives restart. Mirrors the
        // VerifyAUGraph idiom (numbered PASS/FAIL, exit(0) all-pass). `swift run VerifyLibraryStore`.
        // (swift test is broken here; this is the runnable verification for the store path.)
        .executableTarget(
            name: "VerifyLibraryStore",
            dependencies: ["LibraryStore"],
            path: "Sources/VerifyLibraryStore"
        ),
        // B5 verification tool: characterises Apple's AVAudioConverter(.max) SRC — the exact
        // converter the Enhanced (B4) resampler uses — by measuring imaging/aliasing on pure tones.
        // Headless (AVAudioConverter is a pure DSP object, no device). REPLICATES the B4 setup; it
        // imports no app-target code and changes no production audio path. `swift run SRCQualityMeasure`.
        .executableTarget(
            name: "SRCQualityMeasure",
            dependencies: [],
            path: "Sources/SRCQualityMeasure"
        ),
        // Pure-Swift ViewModel tests — uses the Swift Testing framework shipped
        // with CLT (Testing.framework), not XCTest.
        .testTarget(
            name: "AudioViewModelTests",
            dependencies: [],
            path: "Tests/AudioViewModelTests",
            // Source files build together:
            //   AudioViewModelTests.swift                   — original playlist logic tests
            //   MockAudioEngine.swift                       — MockAudioEngine (AudioPlaybackEngineMirror)
            //   AudioEngineProtocolTests.swift              — protocol contract + sort order tests
            //   AutoAdvanceTests.swift                      — redirect comment (split below)
            //   MockAdvanceController.swift                 — state-machine mirror + helpers
            //   AutoAdvanceLinearRepeatShuffleTests.swift   — VM-AA-01..12
            //   AutoAdvanceGaplessSeamTests.swift           — VM-AA-14..19
            //   AutoAdvanceReconfigureGapTests.swift        — VM-AA-RGAP-1, VM-AA-RTR-1
            //   AutoAdvanceDeviceLossTests.swift            — VM-AA-06..07, VM-AA-13, VM-AA-18
            sources: [
                "AudioViewModelTests.swift",
                "MockAudioEngine.swift",
                "AudioEngineProtocolTests.swift",
                "AutoAdvanceTests.swift",
                "MockAdvanceController.swift",
                "AutoAdvanceLinearRepeatShuffleTests.swift",
                "AutoAdvanceGaplessSeamTests.swift",
                "AutoAdvanceReconfigureGapTests.swift",
                "AutoAdvanceDeviceLossTests.swift",
            ],
            swiftSettings: [
                // CommandLineTools ships Testing.framework in a non-standard path.
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-framework", "Testing",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ]
        ),
        // Obj-C++ bridge: wraps EQModule and EQModuleCoefficients in a pure-C
        // interface (EQTestBridge.h) for Swift test consumption.
        //
        // Separated from AudioDSPTests because SwiftPM 5.9 does not support
        // mixed-language source targets (Swift + Obj-C++ in the same directory).
        //
        // Depends on AudioDSP so EQModule.mm is already compiled and linked.
        .target(
            name: "AudioDSPTestBridge",
            dependencies: ["AudioDSP"],
            path: "Sources/AudioDSPTestBridge",
            sources: ["EQTestBridge.mm"],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("../AudioDSP"),
                .headerSearchPath("../AudioDSP/include"),
                .unsafeFlags(["-D_LIBCPP_DISABLE_AVAILABILITY"], .when(platforms: [.macOS])),
                // Intentionally less strict than the production target: the stub module
                // headers (Clarity, Loudness, etc.) have -Wunused-parameter warnings
                // in their stub bodies which are expected.
                .unsafeFlags(["-Wall", "-Wextra", "-fno-exceptions", "-fno-rtti"]),
            ]
        ),
        // DSP integration tests — exercises real EQModule and EQModuleCoefficients
        // through the AudioDSPTestBridge pure-C interface.
        //
        // Uses the Swift Testing framework (same as AudioViewModelTests) so tests
        // run under `swift test` on CLT-only environments without requiring full Xcode.
        //
        // Contains two @Suite structs:
        //   EQTests                      — signal-path tests comparing the Swift reference
        //                                  biquad against the real vDSP-backed EQModule
        //   EQModuleCoefficientsTests    — coefficient-design tests migrated from the
        //                                  standalone EQModuleCoefficientsTests.cpp main()
        .testTarget(
            name: "AudioDSPTests",
            dependencies: ["AudioDSPTestBridge"],
            path: "Tests/AudioDSPTests",
            swiftSettings: [
                // Expose EQTestBridge.h types (CEQParams, CEQBiquadCoeffs, …) and
                // functions (computeEQCoefficientsC, eqModuleProcessC) to Swift.
                .unsafeFlags([
                    "-import-objc-header",
                    "Sources/AudioDSPTestBridge/include/EQTestBridge.h",
                ]),
                // Testing.framework location on CommandLine Tools.
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-framework", "Testing",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ]
        ),
        // Pure-Swift format helper (Sprint 5b, M2-a): maps a channel count to the
        // AVAudioFormat the engine graph is connected at (stereo standard-format path;
        // 5.1 / 7.1 via CoreAudio layout tags). Its own library target so BOTH the app
        // (AdaptiveSound) and the offline gate (VerifyAUGraph) link the identical
        // implementation — no drift in the format logic between them.
        .target(
            name: "AudioFormatKit",
            dependencies: [],
            path: "Sources/AudioFormatKit"
        ),
        .target(
            name: "AudioDSP",
            dependencies: [],
            path: "Sources/AudioDSP",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("include"),
                .unsafeFlags(["-D_LIBCPP_DISABLE_AVAILABILITY"], .when(platforms: [.macOS])),
                .unsafeFlags([
                    "-Wall", "-Wextra", "-Wpedantic",
                    "-Wunused", "-Wshadow", "-Wconversion",
                    "-Wsign-conversion", "-Wnull-dereference",
                    "-Wold-style-cast", "-Wno-exceptions",
                    "-Werror=all", "-Werror=conversion",
                    "-fno-exceptions", "-fno-rtti",
                ], .when(configuration: .debug)),
                .unsafeFlags([
                    "-Wall", "-Wextra",
                    "-fno-exceptions", "-fno-rtti",
                ], .when(configuration: .release)),
                // FFmpeg headers (Homebrew) for the OPTIONAL runtime decode backend (B2b). Headers
                // only — functions resolve via dlopen/dlsym at runtime (no -l link, nothing to
                // bundle). __has_include gates the backend, so a machine without FFmpeg still builds.
                // -isystem (not -I): FFmpeg's third-party headers/macros are exempt from our strict
                // warnings + clang-tidy.
                .unsafeFlags(["-isystem", "/opt/homebrew/include"]),
            ],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation"),
            ]
        ),
    ],
    cxxLanguageStandard: .gnucxx2b
)
