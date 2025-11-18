// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "GoldenImage",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "GoldenImage",
            targets: ["GoldenImage"]
        ),
        .executable(
            name: "golden-image-compare",
            targets: ["GoldenImageCLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "GoldenImage",
            resources: [
                .process("TextureComparison.metal")
            ]
        ),
        .executableTarget(
            name: "GoldenImageCLI",
            dependencies: [
                "GoldenImage",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "GoldenImageTests",
            dependencies: ["GoldenImage"],
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
