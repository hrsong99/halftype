// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Halftype",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Halftype", targets: ["Halftype"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .target(name: "HalftypeCore"),
        // If a first build hangs here, SwiftPM is sending keychain GitHub credentials: add `--disable-keychain`, as the scripts do.
        .binaryTarget(name: "llama",
                      url: "https://github.com/ggml-org/llama.cpp/releases/download/b12167/llama-b12167-xcframework.zip",
                      checksum: "0af08b3039082b1575e6928063636eeb20d80cb5a389b26e37a36bc496a1066e"),
        .target(name: "HalftypeEngine", dependencies: ["HalftypeCore", "llama"]),
        // Language mode 5: state here is confined by hand to one queue, with CF types the compiler can't reason about.
        .target(name: "HalftypeApp", dependencies: ["HalftypeCore", "HalftypeEngine", .product(name: "Sparkle", package: "Sparkle")], resources: [.copy("Logos")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "Halftype", dependencies: ["HalftypeApp"]),
        // Checks against a private window. They need a real run loop, so the test runner can't host them. Not part of the app.
        .executableTarget(name: "halftype-e2e", dependencies: ["HalftypeApp", "HalftypeCore", "HalftypeEngine"], path: "Tests/e2e", swiftSettings: [.swiftLanguageMode(.v5)]),
        // The typing comparison against other apps (bench/compare). Not part of the app; the runner borrows the 2-set table from HalftypeApp.
        .target(name: "CompareKit", dependencies: ["HalftypeCore"], path: "bench/compare/Kit"),
        .executableTarget(name: "halftype-compare", dependencies: ["CompareKit", "HalftypeApp", "HalftypeCore"], path: "bench/compare/Run", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "CompareKitTests", dependencies: ["CompareKit"], path: "bench/compare/Tests"),
        .testTarget(name: "HalftypeAppTests", dependencies: ["HalftypeApp", "HalftypeCore", "HalftypeEngine"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "HalftypeCoreTests", dependencies: ["HalftypeCore"]),
        .testTarget(name: "HalftypeEngineTests", dependencies: ["HalftypeEngine", "HalftypeCore"]),
    ]
)
