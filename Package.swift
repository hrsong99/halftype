// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Itda",
    platforms: [.macOS(.v26)],
    products: [.library(name: "ItdaCore", targets: ["ItdaCore"])],
    targets: [
        .target(name: "ItdaCore"),
        .testTarget(name: "ItdaCoreTests", dependencies: ["ItdaCore"]),
    ]
)
