// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Itda",
    platforms: [.macOS(.v26)],
    products: [.library(name: "ItdaCore", targets: ["ItdaCore"]), .library(name: "ItdaEngine", targets: ["ItdaEngine"]),
               .executable(name: "itda-replay", targets: ["itda-replay"]),
               .executable(name: "Itda", targets: ["ItdaApp"])],
    targets: [
        .target(name: "ItdaCore"),
        .target(name: "TwoSet", dependencies: ["ItdaCore"]),
        .binaryTarget(name: "llama",
                      url: "https://github.com/ggml-org/llama.cpp/releases/download/b12167/llama-b12167-xcframework.zip",
                      checksum: "0af08b3039082b1575e6928063636eeb20d80cb5a389b26e37a36bc496a1066e"),
        .target(name: "ItdaEngine", dependencies: ["ItdaCore", "llama"]),
        .executableTarget(name: "itda-replay", dependencies: ["ItdaCore", "ItdaEngine", "TwoSet"]),
        // Language mode 5: state here is confined by hand to one queue, with CF types the compiler can't reason about.
        .executableTarget(name: "ItdaApp", dependencies: ["ItdaCore", "ItdaEngine"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "ItdaAppTests", dependencies: ["ItdaApp", "ItdaCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "ItdaCoreTests", dependencies: ["ItdaCore", "TwoSet"]),
        .testTarget(name: "ItdaEngineTests", dependencies: ["ItdaEngine", "ItdaCore"]),
        .testTarget(name: "ItdaReplayTests", dependencies: ["itda-replay", "ItdaCore"]),
    ]
)
