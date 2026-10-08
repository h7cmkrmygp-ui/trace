// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EngramKit",
    platforms: [.iOS("27.0"), .macOS("26.0")],
    products: [
        .library(name: "EngramCore", targets: ["EngramCore"]),
    ],
    targets: [
        .target(name: "EngramCore"),
        .target(name: "EngramTesting", dependencies: ["EngramCore"]),
        .testTarget(name: "EngramCoreTests", dependencies: ["EngramCore", "EngramTesting"]),
    ]
)
