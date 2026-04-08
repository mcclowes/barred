// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Barman",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Barman",
            path: "Sources/Barman"
        )
    ]
)
