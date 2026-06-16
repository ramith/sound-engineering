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
            dependencies: ["AudioDSP"],
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
            dependencies: ["AudioDSP"],
            path: "Sources/VerifyAUGraph",
            swiftSettings: [
                .unsafeFlags([
                    "-import-objc-header",
                    "Sources/AudioDSP/include/DeviceBridge.h",
                ]),
            ]
        ),
        // Pure-Swift ViewModel tests — uses the Swift Testing framework shipped
        // with CLT (Testing.framework), not XCTest.
        .testTarget(
            name: "AudioViewModelTests",
            dependencies: [],
            path: "Tests/AudioViewModelTests",
            // All three source files build together:
            //   AudioViewModelTests.swift     — original playlist logic tests
            //   MockAudioEngine.swift         — MockAudioEngine (AudioPlaybackEngineMirror)
            //   AudioEngineProtocolTests.swift — protocol contract + sort order tests
            sources: [
                "AudioViewModelTests.swift",
                "MockAudioEngine.swift",
                "AudioEngineProtocolTests.swift",
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
