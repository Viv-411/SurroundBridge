// swift-tools-version:5.9
// The DSP core as a standalone package so its unit tests can run with `swift test`.
// The app target in SoundPusher.xcodeproj compiles the same source files directly.
import PackageDescription

let package = Package(
    name: "SurroundCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SurroundCore", targets: ["SurroundCore"])],
    targets: [
        .target(name: "SurroundCore", linkerSettings: [.linkedFramework("Accelerate")]),
        .testTarget(name: "SurroundCoreTests", dependencies: ["SurroundCore"]),
    ],
    cxxLanguageStandard: .cxx17
)
