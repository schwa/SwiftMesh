import Metal
import MetalSprockets
import SwiftMesh

// Metal 4 drawing for MetalMesh. Pair `Draw { $0.draw(metalMesh) }` with `.metalMesh(metalMesh)`,
// which binds the vertex buffers and keeps the index buffers resident.

extension MTL4RenderCommandEncoder {
    func draw(_ metalMesh: MetalMesh) {
        for submesh in metalMesh.submeshes {
            let indexSize = submesh.indexType == .uint16 ? 2 : 4
            drawIndexedPrimitives(
                primitiveType: submesh.primitiveType,
                indexCount: submesh.indexCount,
                indexType: submesh.indexType,
                indexBuffer: submesh.indexBuffer.gpuAddress + UInt64(submesh.indexBufferOffset),
                indexBufferLength: submesh.indexCount * indexSize
            )
        }
    }
}

extension Element {
    func metalMesh(_ metalMesh: MetalMesh) -> some Element {
        let withVertexBuffers = metalMesh.vertexBuffers.sorted { $0.key < $1.key }.reduce(AnyElement(self)) { element, entry in
            AnyElement(element.vertexBuffer(entry.value, index: entry.key, offset: metalMesh.vertexBufferOffsets[entry.key] ?? 0))
        }
        return withVertexBuffers.useResources(metalMesh.submeshes.map(\.indexBuffer), usage: .read, stages: .vertex)
    }
}
