import Metal

public enum MetalMeshError: Error {
    case bufferAllocationFailed(length: Int)
}

public extension MetalMesh {
    /// A copy whose submeshes share one 32-bit index buffer, each at its own offset. Vertex buffers are not copied.
    ///
    /// Code that draws the result must add each submesh's ``Submesh/indexBufferOffset``.
    func mergingIndexBuffers() throws -> MetalMesh {
        guard let device = submeshes.first?.indexBuffer.device else {
            return self
        }
        let submeshIndices = submeshes.map(\.indices)
        let allIndices = submeshIndices.flatMap(\.self)
        let length = max(1, MemoryLayout<UInt32>.stride * allIndices.count)
        guard let indexBuffer = allIndices.isEmpty ? device.makeBuffer(length: length) : device.makeBuffer(bytes: allIndices, length: length) else {
            throw MetalMeshError.bufferAllocationFailed(length: length)
        }
        indexBuffer.label = label.map { "\($0) Indices" }

        var merged = self
        var offset = 0
        merged.submeshes = zip(submeshes, submeshIndices).map { submesh, indices in
            var submesh = submesh
            submesh.indexBuffer = indexBuffer
            submesh.indexBufferOffset = offset * MemoryLayout<UInt32>.stride
            submesh.indexCount = indices.count
            submesh.indexType = .uint32
            offset += indices.count
            return submesh
        }
        return merged
    }
}
