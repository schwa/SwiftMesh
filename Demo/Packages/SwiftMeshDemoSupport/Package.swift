// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftMeshDemoSupport",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "SwiftMeshDemoSupport", targets: ["SwiftMeshDemoSupport"]),
    ],
    dependencies: [
        .package(path: "../../.."),
    ],
    targets: [
        .target(
            name: "SwiftMeshDemoSupport",
            dependencies: [
                .product(name: "SwiftMesh", package: "SwiftMesh"),
            ]
        ),
        .testTarget(
            name: "SwiftMeshDemoSupportTests",
            dependencies: ["SwiftMeshDemoSupport"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
