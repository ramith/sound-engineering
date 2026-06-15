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
    // The C++/Obj-C++ sources use C++17 features (std::array, [[maybe_unused]]);
    // declare the standard explicitly so the build matches the code (and the
    // clang-tidy gate, which already runs at gnu++17).
    cxxLanguageStandard: .gnucxx17
)
