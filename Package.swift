// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftMesh",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "SwiftMesh", targets: ["SwiftMesh"]),
    ],
    targets: [
        .target(name: "SwiftMesh"),
        .testTarget(name: "SwiftMeshTests", dependencies: ["SwiftMesh"]),
    ]
)
