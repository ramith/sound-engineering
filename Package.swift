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
                .linkedFramework("Accelerate"),
            ]
        ),
    ]
)
