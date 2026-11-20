// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClaudeSYNC",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ClaudeSYNCCore", targets: ["ClaudeSYNCCore"]),
        .executable(name: "ClaudeSYNC", targets: ["ClaudeSYNC"])
    ],
    targets: [
        .target(
            name: "ClaudeSYNCCore",
            path: "Sources/ClaudeSYNCCore"
        ),
        .executableTarget(
            name: "ClaudeSYNC",
            dependencies: ["ClaudeSYNCCore"],
            path: "Sources/ClaudeSYNC"
        ),
        .testTarget(
            name: "ClaudeSYNCTests",
            dependencies: ["ClaudeSYNCCore"],
            path: "Tests/ClaudeSYNCTests"
        )
    ]
)
