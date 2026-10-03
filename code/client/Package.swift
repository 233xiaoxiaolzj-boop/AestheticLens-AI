// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AestheticLens",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "AestheticLensCore",
            targets: ["AestheticLensCore"]
        )
    ],
    targets: [
        .target(
            name: "AestheticLensCore",
            path: "AestheticLens",
            resources: [
                .process("Resources/luts")
            ]
        )
    ]
)
