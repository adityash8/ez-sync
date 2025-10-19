// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EZSync",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ezsync-cli", targets: ["EZSyncCLI"]),
        .library(name: "EZSyncCore", targets: ["EZSyncCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "5.0.0"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.14.0")
    ],
    targets: [
        .target(
            name: "EZSyncCore",
            dependencies: [
                "SwiftyJSON",
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            path: "Sources/EZSyncCore"
        ),
        .executableTarget(
            name: "EZSyncCLI",
            dependencies: [
                "EZSyncCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/EZSyncCLI"
        ),
        .testTarget(
            name: "EZSyncTests",
            dependencies: ["EZSyncCore"],
            path: "Tests/EZSyncTests"
        )
    ]
)

