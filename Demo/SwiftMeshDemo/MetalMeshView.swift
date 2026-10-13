import GeometryLite3D
import Interaction3D
import Metal
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsUI
import MetalSupport
import simd
import SwiftMesh
import SwiftUI

// MARK: - Render Mode

enum MeshRenderMode: Hashable, Identifiable {
    case blinnPhong
    case debug(MeshDebugMode)
    case topology(TopologyOverlay)

    var id: Self { self }

    var label: String {
        switch self {
        case .blinnPhong: "Blinn-Phong"
        case .debug(let mode): mode.label
        case .topology(let overlay): overlay.label
        }
    }

    /// What the mode shows and when it's useful; used as hover help.
    var helpText: String {
        switch self {
        case .blinnPhong: "Lit, shaded view with three lights."
        case .debug(let mode): mode.helpText
        case .topology(let overlay): overlay.helpText
        }
    }
}

/// Topology views the stock debug shaders can't compute. The data is encoded into texture
/// coordinates and drawn with the Tex Coords debug mode, which shows (u, v, 0) as RGB.
enum TopologyOverlay: CaseIterable, Identifiable {
    /// Red = high valence, green = low (3 is green, 8+ is red).
    case valenceHeatmap
    /// Red at vertices on boundary (open) edges, dim green elsewhere.
    case boundaryEdges

    var id: Self { self }

    var label: String {
        switch self {
        case .valenceHeatmap: "Valence Heatmap"
        case .boundaryEdges: "Boundary Edges"
        }
    }

    var helpText: String {
        switch self {
        case .valenceHeatmap: "Vertex valence: green is low (3), red is high (8 or more). Spots of red or green are poles."
        case .boundaryEdges: "Red where vertices sit on open (boundary) edges. A watertight mesh shows no red."
        }
    }

    func textureCoordinates(for mesh: Mesh) -> [SIMD2<Float>] {
        let topology = mesh.topology
        switch self {
        case .valenceHeatmap:
            let valences = topology.valences
            return topology.halfEdges.map { halfEdge in
                let heat = simd_clamp(Float(valences[halfEdge.origin.raw] - 3) / 5, 0, 1)
                return SIMD2(heat, 1 - heat)
            }

        case .boundaryEdges:
            var onBoundary = [Bool](repeating: false, count: topology.vertices.count)
            for halfEdge in topology.halfEdges where halfEdge.twin == nil && halfEdge.next != nil {
                onBoundary[halfEdge.origin.raw] = true
                if let destination = topology.destViaNext(of: halfEdge.id) {
                    onBoundary[destination.raw] = true
                }
            }
            return topology.halfEdges.map { onBoundary[$0.origin.raw] ? SIMD2(1, 0) : SIMD2(0, 0.3) }
        }
    }
}

/// Wraps `DebugShadersMode` from MetalSprocketsAddOns for use in SwiftUI pickers.
enum MeshDebugMode: Int32, CaseIterable, Identifiable {
    case normal = 0
    case texCoord = 1
    case tangent = 2
    case bitangent = 3
    case worldPosition = 4
    case localPosition = 5
    case faceNormal = 9
    case checkerboard = 11
    case uvGrid = 12
    case depth = 13
    case wireframeOverlay = 14
    case normalDeviation = 15
    case barycentricCoord = 20
    case frontFacing = 21

    var id: Int32 { rawValue }

    var helpText: String {
        switch self {
        case .normal: "Normals as RGB (x, y, z mapped to 0-1). Hard edges show as color jumps."
        case .texCoord: "UVs as red (u) and green (v). Seams show as color jumps."
        case .tangent: "Tangents as RGB. Needs UVs; discontinuities reveal tangent-space seams."
        case .bitangent: "Bitangents as RGB, the third axis of the tangent frame."
        case .worldPosition: "World position as repeating RGB bands."
        case .localPosition: "Object-space position as RGB."
        case .faceNormal: "Flat per-triangle normal as RGB, ignoring stored normals."
        case .checkerboard: "Checkerboard in UV space. Stretched or uneven squares mean UV distortion."
        case .uvGrid: "Grid lines in UV space. Use with the Atlas Baking items to check texel density."
        case .depth: "Distance from the camera as brightness."
        case .wireframeOverlay: "Triangle edges drawn over the surface, showing the triangulation sent to the GPU."
        case .normalDeviation: "How far stored normals differ from the face normal. Bright means heavy smoothing."
        case .barycentricCoord: "Barycentric coordinates per triangle as RGB."
        case .frontFacing: "Front faces and back faces in different colors. Back faces facing you mean flipped winding."
        }
    }

    var debugShadersMode: DebugShadersMode {
        // swiftlint:disable:next force_unwrapping
        DebugShadersMode(rawValue: rawValue)!
    }

    var label: String {
        switch self {
        case .normal: "Normals"
        case .texCoord: "Tex Coords"
        case .tangent: "Tangent"
        case .bitangent: "Bitangent"
        case .worldPosition: "World Position"
        case .localPosition: "Local Position"
        case .faceNormal: "Face Normal"
        case .checkerboard: "Checkerboard"
        case .uvGrid: "UV Grid"
        case .depth: "Depth"
        case .wireframeOverlay: "Wireframe Overlay"
        case .normalDeviation: "Normal Deviation"
        case .barycentricCoord: "Barycentric"
        case .frontFacing: "Front Facing"
        }
    }
}

// MARK: - MetalMeshView

struct MetalMeshView: View {
    let mesh: Mesh
    var animating: Bool = true
    var renderMode: MeshRenderMode = .blinnPhong

    @State private var cameraRotation = simd_quatf(angle: -.pi / 8, axis: [1, 0, 0])
    @State private var cameraDistance: Float = 3
    @State private var cameraTarget: SIMD3<Float> = .zero
    @State private var autoRotation: Float = 0
    @State private var metalMesh: MetalMesh?
    @State private var lighting: Lighting?
    @State private var meshYOffset: Float = 0

    private static let lightPositions: [SIMD3<Float>] = [
        [3, 5, 3],   // Key light — warm, upper right
        [-4, 2, 1],  // Fill light — cool, left side
        [0, 3, -4]   // Rim light — behind and above
    ]

    private var cameraMatrix: simd_float4x4 {
        let rotation = float4x4(cameraRotation)
        let translation = float4x4(translation: cameraTarget)
        let distance = float4x4(translation: [0, 0, cameraDistance])
        return translation * rotation * distance
    }

    var body: some View {
        RenderView { _, drawableSize in
            let aspect = drawableSize.height > 0 ? Float(drawableSize.width / drawableSize.height) : 1.0
            let fov = PerspectiveProjection(verticalAngleOfView: .degrees(45))
            let projectionMatrix = fov.projectionMatrix(aspectRatio: aspect)
            let viewMatrix = cameraMatrix.inverse

            let autoQuat = simd_quatf(angle: autoRotation, axis: simd_normalize(SIMD3<Float>(0.3, 1.0, 0.1)))
            let modelMatrix = float4x4(translation: [0, meshYOffset, 0]) * float4x4(autoQuat)

            let viewProjectionMatrix = projectionMatrix * viewMatrix

            try RenderPass(label: "SwiftMesh Render") {
                GridShader(
                    projectionMatrix: projectionMatrix,
                    cameraMatrix: cameraMatrix,
                    highlightedLines: [
                        .init(axis: .x, position: 0, width: 0.02, color: [1, 0.3, 0.3, 1]),
                        .init(axis: .y, position: 0, width: 0.02, color: [0.3, 0.5, 1, 1])
                    ]
                )

                // Light position crosshairs
                let lightMarker = GraphicsContext3D { ctx in
                    let s: Float = 0.2
                    for p in Self.lightPositions {
                        for axis in [SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 0, 1)] {
                            ctx.stroke(
                                Path3D { path in
                                    path.move(to: p - axis * s)
                                    path.addLine(to: p + axis * s)
                                },
                                with: .yellow,
                                lineWidth: 2
                            )
                        }
                    }
                }
                let viewport = SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
                GraphicsContext3DRenderPipeline(
                    context: lightMarker,
                    viewProjection: viewProjectionMatrix,
                    viewport: viewport
                )

                if let metalMesh {
                    switch renderMode {
                    case .blinnPhong:
                        if let lighting {
                            try BlinnPhongShader {
                                try Draw { encoder in
                                    encoder.draw(metalMesh)
                                }
                                .metalMesh(metalMesh)
                                .blinnPhongMaterial(BlinnPhongMaterial(
                                    ambient: .color([0.05, 0.06, 0.08]),
                                    diffuse: .color([0.45, 0.55, 0.65]),
                                    specular: .color([0.9, 0.9, 0.95]),
                                    shininess: 80
                                ))
                                .blinnPhongMatrices(
                                    projectionMatrix: projectionMatrix,
                                    viewMatrix: viewMatrix,
                                    modelMatrix: modelMatrix,
                                    cameraMatrix: cameraMatrix
                                )
                                .lighting(lighting)
                            }
                            .vertexDescriptor(MTLVertexDescriptor(metalMesh.vertexDescriptor))
                            .depthCompare(function: .less, enabled: true)
                        }

                    case .debug, .topology:
                        let debugMode: MeshDebugMode = if case .debug(let mode) = renderMode { mode } else { .texCoord }
                        let upperLeft = simd_float3x3(
                            SIMD3<Float>(modelMatrix.columns.0.x, modelMatrix.columns.0.y, modelMatrix.columns.0.z),
                            SIMD3<Float>(modelMatrix.columns.1.x, modelMatrix.columns.1.y, modelMatrix.columns.1.z),
                            SIMD3<Float>(modelMatrix.columns.2.x, modelMatrix.columns.2.y, modelMatrix.columns.2.z)
                        )
                        let normalMatrix: simd_float3x3 = {
                            let det = upperLeft.determinant
                            guard abs(det) > 1e-8 else {
                                return upperLeft
                            }
                            return upperLeft.inverse.transpose
                        }()

                        try DebugRenderPipeline(
                            modelMatrix: modelMatrix,
                            normalMatrix: normalMatrix,
                            debugMode: debugMode.debugShadersMode,
                            lightPosition: [2, 3, 2],
                            cameraPosition: cameraMatrix.columns.3.xyz,
                            viewProjectionMatrix: viewProjectionMatrix
                        ) {
                            Draw { encoder in
                                encoder.draw(metalMesh)
                            }
                            .metalMesh(metalMesh)
                        }
                        .vertexDescriptor(MTLVertexDescriptor(metalMesh.vertexDescriptor))
                        .depthCompare(function: .less, enabled: true)
                    }
                }
            }
        }
        .metalClearColor(MTLClearColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1))
        .metalDepthStencilPixelFormat(.depth32Float)
        .interactiveCamera(
            rotation: $cameraRotation,
            distance: $cameraDistance,
            target: $cameraTarget
        )
        .onChange(of: mesh) {
            prepareMesh()
        }
        .onChange(of: renderMode) {
            prepareMesh()
        }
        .onChange(of: animating) { _, newValue in
            if newValue {
                startAnimationTimer()
            }
        }
        .onAppear {
            prepareMesh()
            setupLighting()
            if animating {
                startAnimationTimer()
            }
        }
    }

    private func prepareMesh() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return
        }
        var prepared = mesh
        if prepared.normals == nil {
            prepared = prepared.withFlatNormals()
        }
        if prepared.textureCoordinates == nil {
            prepared = prepared.withSphericalUVs()
        }
        if prepared.tangents == nil || prepared.bitangents == nil {
            prepared = prepared.withTangents()
        }
        if case .topology(let overlay) = renderMode {
            prepared.textureCoordinates = overlay.textureCoordinates(for: prepared)
        }
        // Lift mesh so its bottom sits on the ground plane
        let (lo, _) = prepared.bounds
        meshYOffset = -lo.y
        metalMesh = MetalMesh(mesh: prepared, device: device, label: "MetalMeshView")
    }

    private func setupLighting() {
        lighting = try? Lighting(
            ambientLightColor: [0.15, 0.15, 0.18],
            lights: [
                (Self.lightPositions[0], Light(type: .spot, color: [1.0, 0.95, 0.85], intensity: 35)),
                (Self.lightPositions[1], Light(type: .spot, color: [0.6, 0.7, 0.9], intensity: 15)),
                (Self.lightPositions[2], Light(type: .spot, color: [0.9, 0.9, 1.0], intensity: 20))
            ]
        )
    }

    private func startAnimationTimer() {
        Task { @MainActor in
            while animating {
                try? await Task.sleep(for: .milliseconds(16))
                if animating {
                    autoRotation += 0.01
                }
            }
        }
    }
}
