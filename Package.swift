// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Barred",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Barred",
            path: "Sources/Barred",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=complete")
            ]
        ),
        .testTarget(
            name: "BarredTests",
            dependencies: ["Barred"],
            path: "Tests/BarredTests",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=complete")
            ]
        )
    ]
)
