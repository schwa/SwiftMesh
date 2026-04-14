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
    dependencies: [
        .package(url: "https://github.com/schwa/GeometryLite2D", from: "0.0.1"),
        .package(url: "https://github.com/schwa/GeometryLite3D", from: "0.1.0"),
        .package(url: "https://github.com/schwa/MetalSupport", from: "1.0.1"),
        .package(url: "https://github.com/schwa/SwiftEarcut", from: "0.0.1"),
    ],
    targets: [
        .target(
            name: "SwiftMesh",
            dependencies: [
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSupport", package: "MetalSupport"),
                .product(name: "SwiftEarcut", package: "SwiftEarcut"),
                "MikkTSpace",
            ]
        ),
        .target(
            name: "MikkTSpace",
            publicHeadersPath: "."
        ),
        .testTarget(name: "SwiftMeshTests", dependencies: ["SwiftMesh"]),
    ]
)
