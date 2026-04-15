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

    var id: Self { self }

    var label: String {
        switch self {
        case .blinnPhong: "Blinn-Phong"
        case .debug(let mode): mode.label
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

                if let metalMesh {
                    switch renderMode {
                    case .blinnPhong:
                        if let lighting {
                            try BlinnPhongShader {
                                try Draw { encoder in
                                    encoder.draw(metalMesh)
                                }
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

                    case .debug(let debugMode):
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
        // Lift mesh so its bottom sits on the ground plane
        let (lo, _) = prepared.bounds
        meshYOffset = -lo.y
        metalMesh = MetalMesh(mesh: prepared, device: device, label: "MetalMeshView")
    }

    private func setupLighting() {
        lighting = try? Lighting(
            ambientLightColor: [0.15, 0.15, 0.18],
            lights: [
                // Key light — warm, upper right
                ([3, 5, 3], Light(type: .spot, color: [1.0, 0.95, 0.85], intensity: 35)),
                // Fill light — cool, left side
                ([-4, 2, 1], Light(type: .spot, color: [0.6, 0.7, 0.9], intensity: 15)),
                // Rim light — behind and above
                ([0, 3, -4], Light(type: .spot, color: [0.9, 0.9, 1.0], intensity: 20))
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
