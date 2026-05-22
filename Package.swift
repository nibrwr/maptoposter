// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MapToPosterMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MapToPosterMac", targets: ["MapToPosterMac"])
    ],
    targets: [
        .executableTarget(
            name: "MapToPosterMac",
            path: "Sources/MapToPosterMac",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "MapToPosterMacTests",
            dependencies: ["MapToPosterMac"],
            path: "Tests/MapToPosterMacTests"
        )
    ]
)
