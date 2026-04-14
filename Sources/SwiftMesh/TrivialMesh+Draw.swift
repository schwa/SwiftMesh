import Metal
import MetalKit

public extension MTLRenderCommandEncoder {
    func setVertexBuffers(of mesh: LegacyMesh) {
        for (index, buffer) in mesh.vertexBuffers.enumerated() {
            setVertexBuffer(buffer.buffer, offset: buffer.offset, index: index)
        }
    }
}
