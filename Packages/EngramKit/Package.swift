// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EngramKit",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "EngramCore", targets: ["EngramCore"]),
        .library(name: "EngramStore", targets: ["EngramStore"]),
        .library(name: "EngramPipeline", targets: ["EngramPipeline"]),
        .library(name: "EngramIntelligence", targets: ["EngramIntelligence"]),
        .library(name: "EngramCapture", targets: ["EngramCapture"]),
        .library(name: "EngramCalendar", targets: ["EngramCalendar"]),
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
        .target(name: "EngramPipeline", dependencies: ["EngramCore", "EngramStore"]),
        .target(name: "EngramIntelligence", dependencies: ["EngramCore"]),
        .target(name: "EngramCapture", dependencies: ["EngramCore"]),
        .target(name: "EngramCalendar"),
        .target(name: "EngramTesting", dependencies: ["EngramCore"]),
        .testTarget(name: "EngramCoreTests", dependencies: ["EngramCore", "EngramTesting"]),
        .testTarget(
            name: "EngramStoreTests",
            dependencies: ["EngramStore", "EngramCore", "EngramTesting", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "EngramPipelineTests",
            dependencies: ["EngramPipeline", "EngramStore", "EngramCore", "EngramTesting"]
        ),
        .testTarget(name: "EngramIntelligenceTests", dependencies: ["EngramIntelligence", "EngramCore"]),
        .testTarget(name: "EngramCaptureTests", dependencies: ["EngramCapture", "EngramTesting"]),
    ]
)
