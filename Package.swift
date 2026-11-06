// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Itda",
    platforms: [.macOS(.v26)],
    products: [.library(name: "ItdaCore", targets: ["ItdaCore"]), .executable(name: "Itda", targets: ["ItdaApp"])],
    targets: [
        .target(name: "ItdaCore"),
        // Language mode 5: state here is confined by hand to one queue, with CF types the compiler can't reason about.
        .executableTarget(name: "ItdaApp", dependencies: ["ItdaCore", "ItdaEngine"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "ItdaAppTests", dependencies: ["ItdaApp", "ItdaCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "ItdaCoreTests", dependencies: ["ItdaCore"]),
    ]
)
