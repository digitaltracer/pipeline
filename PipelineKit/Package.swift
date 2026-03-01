// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PipelineKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "PipelineKit",
            targets: ["PipelineKit"]
        )
    ],
    targets: [
        .target(
            name: "PipelineKit"
        ),
        .testTarget(
            name: "PipelineKitTests",
            dependencies: ["PipelineKit"]
        )
    ]
)
