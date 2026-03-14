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
    dependencies: [
        .package(url: "https://github.com/google/GoogleSignIn-iOS", from: "9.0.0")
    ],
    targets: [
        .target(
            name: "PipelineKit",
            dependencies: [
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS")
            ]
        ),
        .testTarget(
            name: "PipelineKitTests",
            dependencies: ["PipelineKit"]
        )
    ]
)
