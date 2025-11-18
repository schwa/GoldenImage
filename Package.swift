// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GoldenImage",
    platforms: [
        .macOS(.v13)
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
    targets: [
        
        
        .target(
            name: "GoldenImage",
            resources: [
                .process("TextureComparison.metal")
            ]
        ),
        .executableTarget(
            name: "GoldenImageCLI",
            dependencies: ["GoldenImage"]
        ),
        .testTarget(
            name: "GoldenImageTests",
            dependencies: ["GoldenImage"],
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)
