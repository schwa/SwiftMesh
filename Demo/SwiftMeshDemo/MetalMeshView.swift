import GeometryLite3D
import Interaction3D
import Metal
import MetalKit
import MetalSupport
import OrderedCollections
import simd
import SwiftMesh
import SwiftUI

// MARK: - Debug Mode

/// Must match the DebugMode enum in MeshShaders.metal.
enum MeshDebugMode: UInt32, CaseIterable, Identifiable {
    case shaded = 0
    case normals = 1
    case texCoords = 2
    case frontFacing = 3
    case faceNormals = 4
    case depth = 5
    case checkerboard = 6
    case barycentric = 7

    var id: UInt32 { rawValue }

    var label: String {
        switch self {
        case .shaded: "Shaded"
        case .normals: "Normals"
        case .texCoords: "Tex Coords"
        case .frontFacing: "Front Facing"
        case .faceNormals: "Face Normals"
        case .depth: "Depth"
        case .checkerboard: "Checkerboard"
        case .barycentric: "Barycentric"
        }
    }
}

// MARK: - MetalMeshView (SwiftUI, with gestures)

/// A SwiftUI view that renders a `Mesh` using Metal with debug visualization and interactive camera.
struct MetalMeshView: View {
    let mesh: Mesh
    var animating: Bool = true
    var debugMode: MeshDebugMode = .shaded

    @State private var cameraRotation = simd_quatf(angle: 0, axis: [0, 1, 0])
    @State private var cameraDistance: Float = 3
    @State private var cameraTarget: SIMD3<Float> = .zero

    var body: some View {
        MetalMeshMTKView(
            mesh: mesh,
            animating: animating,
            debugMode: debugMode,
            userRotation: cameraRotation,
            cameraDistance: cameraDistance,
            cameraTarget: cameraTarget
        )
        .interactiveCamera(
            rotation: $cameraRotation,
            distance: $cameraDistance,
            target: $cameraTarget
        )
    }
}

// MARK: - MTKView wrapper (internal)

private struct MetalMeshMTKView: NSViewRepresentable {
    let mesh: Mesh
    var animating: Bool
    var debugMode: MeshDebugMode
    var userRotation: simd_quatf
    var cameraDistance: Float
    var cameraTarget: SIMD3<Float>

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = context.coordinator.device
        mtkView.delegate = context.coordinator
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1)
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        return mtkView
    }

    func updateNSView(_: MTKView, context: Context) {
        context.coordinator.updateMesh(mesh, device: context.coordinator.device)
        context.coordinator.animating = animating
        context.coordinator.debugMode = debugMode
        context.coordinator.userRotation = userRotation
        context.coordinator.cameraDistance = cameraDistance
        context.coordinator.cameraTarget = cameraTarget
    }

    func makeCoordinator() -> MetalMeshRenderer {
        MetalMeshRenderer(mesh: mesh, animating: animating, debugMode: debugMode)
    }
}

// MARK: - Uniforms

struct MeshUniforms {
    var modelViewProjectionMatrix: simd_float4x4
    var normalMatrix: simd_float3x3
    var debugMode: UInt32
    var _pad0: UInt32 = 0
    var _pad1: UInt32 = 0
    var _pad2: UInt32 = 0
}

// MARK: - Renderer

class MetalMeshRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState?
    var depthState: MTLDepthStencilState?

    var metalMesh: MetalMesh?
    var interleavedBuffer: MTLBuffer?
    var autoRotation: Float = 0
    var animating: Bool = true
    var debugMode: MeshDebugMode = .shaded
    var userRotation = simd_quatf(angle: 0, axis: [0, 1, 0])
    var cameraDistance: Float = 3
    var cameraTarget: SIMD3<Float> = .zero

    init(mesh: Mesh, animating: Bool = true, debugMode: MeshDebugMode = .shaded) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("No Metal device available")
        }
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            fatalError("Failed to create command queue")
        }
        self.commandQueue = queue
        self.animating = animating
        self.debugMode = debugMode
        super.init()
        buildPipeline()
        buildDepthState()
        updateMesh(mesh, device: device)
    }

    func updateMesh(_ mesh: Mesh, device: MTLDevice) {
        var prepared = mesh
        if prepared.normals == nil {
            prepared = prepared.withFlatNormals()
        }
        if prepared.textureCoordinates == nil {
            prepared = prepared.withSphericalUVs()
        }
        let newMetalMesh = MetalMesh(mesh: prepared, device: device, label: "MetalMeshView")
        metalMesh = newMetalMesh
        interleavedBuffer = buildInterleavedBuffer(metalMesh: newMetalMesh)
    }

    private func buildPipeline() {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to load default Metal library")
        }
        guard let vertexFunction = library.makeFunction(name: "mesh_vertex") else {
            fatalError("Failed to find vertex function 'mesh_vertex'")
        }
        guard let fragmentFunction = library.makeFunction(name: "mesh_fragment") else {
            fatalError("Failed to find fragment function 'mesh_fragment'")
        }

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 3
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[2].format = .float2
        vertexDescriptor.attributes[2].offset = MemoryLayout<Float>.size * 6
        vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 8
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
    }

    private func buildDepthState() {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: descriptor)
    }

    // MARK: - MTKViewDelegate

    func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {
    }

    func draw(in view: MTKView) {
        guard let pipelineState, let depthState, let metalMesh, let interleavedBuffer else {
            return
        }
        guard let drawable = view.currentDrawable, let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        if animating {
            autoRotation += 0.01
        }

        let aspect = Float(view.drawableSize.width / view.drawableSize.height)
        let fov = PerspectiveProjection(verticalAngleOfView: .degrees(45))
        let projectionMatrix = fov.projectionMatrix(aspectRatio: aspect)

        // View matrix: same pattern as the wireframe renderer
        let rotationMatrix = float4x4(userRotation)
        let viewMatrix = (float4x4(translation: cameraTarget) * rotationMatrix * float4x4(translation: [0, 0, cameraDistance])).inverse

        // Auto-rotation applies to the model
        let autoQuat = simd_quatf(angle: autoRotation, axis: simd_normalize(SIMD3<Float>(0.3, 1.0, 0.1)))
        let modelMatrix = float4x4(autoQuat)

        let mvpMatrix = projectionMatrix * viewMatrix * modelMatrix
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

        var uniforms = MeshUniforms(
            modelViewProjectionMatrix: mvpMatrix,
            normalMatrix: normalMatrix,
            debugMode: debugMode.rawValue
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.back)
        encoder.setFrontFacing(.counterClockwise)

        encoder.setVertexBuffer(interleavedBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<MeshUniforms>.size, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MeshUniforms>.size, index: 0)

        for submesh in metalMesh.submeshes {
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: submesh.indexCount,
                indexType: .uint32,
                indexBuffer: submesh.indexBuffer,
                indexBufferOffset: 0
            )
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Vertex Buffer

    private func buildInterleavedBuffer(metalMesh: MetalMesh) -> MTLBuffer? {
        let descriptor = metalMesh.vertexDescriptor

        guard let posAttr = descriptor.attributes.first(where: { $0.semantic == .position }) else {
            return nil
        }
        let normalAttr = descriptor.attributes.first { $0.semantic == .normal }
        let texcoordAttr = descriptor.attributes.first { $0.semantic == .texcoord }

        let count = metalMesh.vertexCount
        let floatsPerVertex = 8
        let outStride = MemoryLayout<Float>.size * floatsPerVertex
        guard let buffer = device.makeBuffer(length: count * outStride) else {
            return nil
        }
        let outPtr = buffer.contents().assumingMemoryBound(to: Float.self)

        for vi in 0..<count {
            let base = vi * floatsPerVertex

            let posBuffer = metalMesh.vertexBuffers[posAttr.bufferIndex]!
            let posStride = descriptor.layouts[posAttr.bufferIndex]!.stride
            let posPtr = posBuffer.contents().advanced(by: vi * posStride + posAttr.offset)
                .assumingMemoryBound(to: Float.self)
            outPtr[base + 0] = posPtr[0]
            outPtr[base + 1] = posPtr[1]
            outPtr[base + 2] = posPtr[2]

            if let normalAttr {
                let normBuffer = metalMesh.vertexBuffers[normalAttr.bufferIndex]!
                let normStride = descriptor.layouts[normalAttr.bufferIndex]!.stride
                let normPtr = normBuffer.contents().advanced(by: vi * normStride + normalAttr.offset)
                    .assumingMemoryBound(to: Float.self)
                outPtr[base + 3] = normPtr[0]
                outPtr[base + 4] = normPtr[1]
                outPtr[base + 5] = normPtr[2]
            } else {
                outPtr[base + 3] = 0
                outPtr[base + 4] = 1
                outPtr[base + 5] = 0
            }

            if let texcoordAttr {
                let uvBuffer = metalMesh.vertexBuffers[texcoordAttr.bufferIndex]!
                let uvStride = descriptor.layouts[texcoordAttr.bufferIndex]!.stride
                let uvPtr = uvBuffer.contents().advanced(by: vi * uvStride + texcoordAttr.offset)
                    .assumingMemoryBound(to: Float.self)
                outPtr[base + 6] = uvPtr[0]
                outPtr[base + 7] = uvPtr[1]
            } else {
                outPtr[base + 6] = 0
                outPtr[base + 7] = 0
            }
        }

        return buffer
    }
}
