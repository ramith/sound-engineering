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
            ]
        ),
        // Pure-Swift ViewModel tests — no C++ dependency, builds independently.
        // AudioViewModel lives in the AdaptiveSound executable target which
        // cannot be @testable-imported; tests exercise a local mock that mirrors
        // the exact playTrack(at:) logic.  Move to @testable import when
        // AudioViewModel is extracted into a library target (Phase 1.5).
        .testTarget(
            name: "AudioViewModelTests",
            dependencies: [],
            path: "Tests/AudioViewModelTests",
            swiftSettings: [
                // CommandLineTools ships Testing.framework in a non-standard path.
                // Xcode's full toolchain finds it automatically; CLT needs the hint.
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
    // C++23 (GNU dialect, for Apple ObjC++ extensions). Verified on Apple
    // clang 21 / libc++: std::span, std::mdspan, std::expected, ranges all
    // available; std::float32_t and std::generator are not yet in Apple libc++.
    // Kept in sync with the clang-tidy gate (.githooks/pre-commit runs gnu++2b).
    cxxLanguageStandard: .gnucxx2b
)
