// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EngramKit",
    platforms: [.iOS("27.0"), .macOS("26.0")],
    products: [
        .library(name: "EngramCore", targets: ["EngramCore"]),
        .library(name: "EngramStore", targets: ["EngramStore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(name: "EngramCore"),
        .target(
            name: "EngramStore",
            dependencies: ["EngramCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(name: "EngramTesting", dependencies: ["EngramCore"]),
        .testTarget(name: "EngramCoreTests", dependencies: ["EngramCore", "EngramTesting"]),
        .testTarget(
            name: "EngramStoreTests",
            dependencies: ["EngramStore", "EngramCore", "EngramTesting", .product(name: "GRDB", package: "GRDB.swift")]
        ),
    ]
)
