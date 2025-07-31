// swift-tools-version: 5.6

import PackageDescription

let package = Package(
    name: "Tracklytic",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        .library(
            name: "Tracklytic",
            targets: ["Tracklytic"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Tracklytic",
            dependencies: []),
        .testTarget(
            name: "TracklyticTests",
            dependencies: ["Tracklytic"]),
    ]
)
