import GeometryLite3D
import Metal
import MetalKit
import MetalSupport
import OrderedCollections
import simd
import SwiftMesh
import SwiftUI

// MARK: - MetalMeshView (SwiftUI)

/// A SwiftUI view that renders a `Mesh` using Metal with flat shading.
struct MetalMeshView: NSViewRepresentable {
    let mesh: Mesh
    var animating: Bool = true

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
    }

    func makeCoordinator() -> MetalMeshRenderer {
        MetalMeshRenderer(mesh: mesh, animating: animating)
    }
}

// MARK: - Uniforms

struct MeshUniforms {
    var modelViewProjectionMatrix: simd_float4x4
    var normalMatrix: simd_float3x3
}

// MARK: - Renderer

class MetalMeshRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState?
    var depthState: MTLDepthStencilState?

    var metalMesh: MetalMesh?
    var rotation: Float = 0
    var animating: Bool = true

    init(mesh: Mesh, animating: Bool = true) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("No Metal device available")
        }
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            fatalError("Failed to create command queue")
        }
        self.commandQueue = queue
        self.animating = animating
        super.init()
        buildPipeline()
        buildDepthState()
        updateMesh(mesh, device: device)
    }

    func updateMesh(_ mesh: Mesh, device: MTLDevice) {
        // Ensure the mesh has normals for shading
        let meshWithNormals: Mesh
        if mesh.normals != nil {
            meshWithNormals = mesh
        } else {
            meshWithNormals = mesh.withFlatNormals()
        }
        metalMesh = MetalMesh(mesh: meshWithNormals, device: device, label: "MetalMeshView")
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
        // Attribute 0: position (float3)
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        // Attribute 1: normal (float3)
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 3
        vertexDescriptor.attributes[1].bufferIndex = 0
        // Layout 0: interleaved position + normal
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 6
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
        guard let pipelineState, let depthState, let metalMesh else {
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

        // Animate rotation
        if animating {
            rotation += 0.01
        }

        // Build matrices
        let aspect = Float(view.drawableSize.width / view.drawableSize.height)
        let fov = PerspectiveProjection(verticalAngleOfView: .degrees(45))
        let projectionMatrix = fov.projectionMatrix(aspectRatio: aspect)

        let viewMatrix = (float4x4(translation: [0, 0, 3])).inverse
        let modelMatrix = float4x4(simd_quatf(angle: rotation, axis: simd_normalize(SIMD3<Float>(0.3, 1.0, 0.1))))

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
            normalMatrix: normalMatrix
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.back)
        encoder.setFrontFacing(.counterClockwise)

        // Build a flat interleaved buffer: position (float3) + normal (float3) per vertex
        // We need to re-pack because MetalMesh may have different layouts
        let vertexBuffer = buildInterleavedBuffer(metalMesh: metalMesh)
        if let vertexBuffer {
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        }
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<MeshUniforms>.size, index: 1)

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

    /// Re-pack MetalMesh vertex data into a flat position+normal interleaved buffer.
    private func buildInterleavedBuffer(metalMesh: MetalMesh) -> MTLBuffer? {
        let descriptor = metalMesh.vertexDescriptor

        // Find position and normal attributes
        guard let posAttr = descriptor.attributes.first(where: { $0.semantic == .position }) else {
            return nil
        }
        let normalAttr = descriptor.attributes.first { $0.semantic == .normal }

        let count = metalMesh.vertexCount
        let outStride = MemoryLayout<Float>.size * 6 // position(3) + normal(3)
        guard let buffer = device.makeBuffer(length: count * outStride) else {
            return nil
        }
        let outPtr = buffer.contents().assumingMemoryBound(to: Float.self)

        for vi in 0..<count {
            // Read position
            let posBuffer = metalMesh.vertexBuffers[posAttr.bufferIndex]!
            let posStride = descriptor.layouts[posAttr.bufferIndex]!.stride
            let posPtr = posBuffer.contents().advanced(by: vi * posStride + posAttr.offset)
                .assumingMemoryBound(to: Float.self)
            outPtr[vi * 6 + 0] = posPtr[0]
            outPtr[vi * 6 + 1] = posPtr[1]
            outPtr[vi * 6 + 2] = posPtr[2]

            // Read normal (or zero)
            if let normalAttr {
                let normBuffer = metalMesh.vertexBuffers[normalAttr.bufferIndex]!
                let normStride = descriptor.layouts[normalAttr.bufferIndex]!.stride
                let normPtr = normBuffer.contents().advanced(by: vi * normStride + normalAttr.offset)
                    .assumingMemoryBound(to: Float.self)
                outPtr[vi * 6 + 3] = normPtr[0]
                outPtr[vi * 6 + 4] = normPtr[1]
                outPtr[vi * 6 + 5] = normPtr[2]
            } else {
                outPtr[vi * 6 + 3] = 0
                outPtr[vi * 6 + 4] = 1
                outPtr[vi * 6 + 5] = 0
            }
        }

        return buffer
    }
}
