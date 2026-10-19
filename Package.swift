// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftMesh",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(name: "SwiftMesh", targets: ["SwiftMesh"]),
        .library(name: "SwiftMeshIO", targets: ["SwiftMeshIO"]),
        .library(name: "SwiftMeshMikkTSpace", targets: ["SwiftMeshMikkTSpace"])
    ],
    dependencies: [
        .package(url: "https://github.com/schwa/GeometryLite2D", .upToNextMinor(from: "0.0.4")),
        .package(url: "https://github.com/schwa/GeometryLite3D", .upToNextMinor(from: "0.2.5")),
        .package(url: "https://github.com/schwa/MetalSupport", .upToNextMinor(from: "1.0.7"))
    ],
    targets: [
        .target(
            name: "SwiftMesh",
            dependencies: [
                .product(name: "Geometry", package: "GeometryLite2D"),
                .product(name: "GeometryLite3D", package: "GeometryLite3D"),
                .product(name: "MetalSupport", package: "MetalSupport"),
                "SwiftMeshMikkTSpace",
                "BinPacking"
            ],
            resources: [
                .copy("Resources/teapot.obj")
            ]
        ),
        .target(
            name: "SwiftMeshMikkTSpace",
            publicHeadersPath: "."
        ),
        .target(
            name: "SwiftMeshIO",
            dependencies: ["SwiftMesh"]
        ),
        .target(name: "BinPacking"),
        .executableTarget(name: "SwiftMeshBenchmarks", dependencies: ["SwiftMesh", "SwiftMeshIO", "BinPacking", .product(name: "Geometry", package: "GeometryLite2D"), .product(name: "GeometryLite3D", package: "GeometryLite3D")]),
        .testTarget(name: "SwiftMeshTests", dependencies: ["SwiftMesh", "BinPacking"], resources: [.copy("Resources/ManifoldPolygons")]),
        .testTarget(name: "SwiftMeshIOTests", dependencies: ["SwiftMeshIO"]),
        .testTarget(name: "BinPackingTests", dependencies: ["BinPacking"])
    ]
)
