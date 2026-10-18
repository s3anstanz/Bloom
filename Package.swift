// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Bloom",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "BloomCore"),
        .executableTarget(name: "Bloom", dependencies: ["BloomCore"]),
        .testTarget(name: "BloomCoreTests", dependencies: ["BloomCore"]),
    ]
)
