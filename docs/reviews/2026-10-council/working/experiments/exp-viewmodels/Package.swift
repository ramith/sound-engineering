// swift-tools-version:6.2
import PackageDescription
let package = Package(name: "T", platforms: [.macOS(.v26)], targets: [
 .executableTarget(name: "App", path: "Sources/App"),
 .testTarget(name: "AppTests", dependencies: ["App"], path: "Tests/AppTests")])
