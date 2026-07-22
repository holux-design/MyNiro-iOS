// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BetterBlueKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v11)
    ],
    products: [
        .library(
            name: "BetterBlueKit",
            targets: ["BetterBlueKit"]
        )
    ],
    targets: [
        .target(
            name: "BetterBlueKit",
            dependencies: [],
            path: "Sources/BetterBlueKit",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .define("RELEASE", .when(configuration: .release))
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
