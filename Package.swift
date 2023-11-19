// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MediaIO",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MediaIO",
            targets: ["MediaIO"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.3"),
    ],
    targets: [
        .target(
            name: "MediaIO",
            dependencies: [
                .product(name: "Logging", package: "swift-log")
            ],
            sources: [
                "Demux",
                "FLV",
                "ISO",
                "Mux",
                "Net",
                "RTMP",
                "Util",
                "Extension"
            ]),
        .testTarget(
            name: "MediaIOTests",
            dependencies: ["MediaIO"]),
        .executableTarget(
            name: "mio",
            dependencies: [
                .target(name: "MediaIO"),
                .product(name: "Logging", package: "swift-log")
            ]
        )
    ]
)
