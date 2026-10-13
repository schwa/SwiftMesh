import Metal
import MetalSupport

public extension MetalMesh {
    /// Every attribute in ``vertexDescriptor``, read back from the vertex buffers into tightly packed arrays.
    ///
    /// The vertex buffers must be CPU-visible (shared or managed storage).
    func vertexAttributeData() -> [VertexAttributeData] {
        vertexDescriptor.attributes.map { attribute in
            guard let buffer = vertexBuffers[attribute.bufferIndex], let layout = vertexDescriptor.layouts[attribute.bufferIndex] else {
                fatalError("MetalMesh has no vertex buffer or layout at index \(attribute.bufferIndex)")
            }
            let size = attribute.format.size
            let start = buffer.contents() + (vertexBufferOffsets[attribute.bufferIndex] ?? 0) + attribute.offset
            var bytes = [UInt8](repeating: 0, count: size * vertexCount)
            bytes.withUnsafeMutableBytes { destination in
                for vertex in 0..<vertexCount {
                    (destination.baseAddress! + vertex * size).copyMemory(from: start + vertex * layout.stride, byteCount: size)
                }
            }
            return VertexAttributeData(semantic: attribute.semantic, format: attribute.format, bytes: bytes, count: vertexCount)
        }
    }

    /// Copies of `meshes` whose vertex data shares one buffer per vertex buffer index, each mesh at its own offset
    /// (``vertexBufferOffsets``). Index buffers are not changed.
    ///
    /// All meshes must have the same ``vertexDescriptor``. Code that draws the result must bind each mesh's vertex
    /// buffers at its offsets, or use offset / stride as a base vertex.
    static func packingVertexBuffers(_ meshes: [MetalMesh]) throws -> [MetalMesh] {
        guard let first = meshes.first, let device = first.vertexBuffers.values.first?.device else {
            return meshes
        }
        precondition(meshes.allSatisfy { $0.vertexDescriptor == first.vertexDescriptor }, "packingVertexBuffers needs meshes with the same vertex descriptor")

        var packed = meshes
        for (bufferIndex, layout) in first.vertexDescriptor.layouts {
            let lengths = meshes.map { $0.vertexCount * layout.stride }
            let length = max(1, lengths.reduce(0, +))
            guard let shared = device.makeBuffer(length: length, options: .storageModeShared) else {
                throw MetalMeshError.bufferAllocationFailed(length: length)
            }
            shared.label = first.label.map { "\($0) Vertices[\(bufferIndex)] (packed)" }
            var offset = 0
            for (index, mesh) in meshes.enumerated() {
                guard let source = mesh.vertexBuffers[bufferIndex] else {
                    fatalError("MetalMesh has no vertex buffer at index \(bufferIndex)")
                }
                (shared.contents() + offset).copyMemory(from: source.contents() + (mesh.vertexBufferOffsets[bufferIndex] ?? 0), byteCount: lengths[index])
                packed[index].vertexBuffers[bufferIndex] = shared
                packed[index].vertexBufferOffsets[bufferIndex] = offset
                offset += lengths[index]
            }
        }
        return packed
    }
}
