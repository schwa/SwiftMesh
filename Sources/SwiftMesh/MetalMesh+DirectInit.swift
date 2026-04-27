import GeometryLite3D
import Metal
import MetalSupport
import simd

// MARK: - Direct initializers (bypass Mesh / topology)

public extension MetalMesh {
    /// Create a `MetalMesh` directly from in-memory attribute arrays and an
    /// index list, skipping the half-edge topology / dedup / triangulation
    /// pipeline.
    ///
    /// Use this when you already have GPU-ready, per-vertex attribute arrays
    /// (e.g. from a third-party loader, procedural geometry, or ARKit mesh
    /// anchors) and you don't need a `Mesh` for editing.
    ///
    /// The resulting mesh has a single submesh covering all indices and uses
    /// the same `VertexDescriptor` shape that `MetalMesh(mesh:device:)` would
    /// produce for the same set of attributes.
    ///
    /// - Parameters:
    ///   - device: The Metal device used to allocate buffers.
    ///   - positions: Per-vertex positions. Required.
    ///   - normals: Optional per-vertex normals. Must match `positions.count` if non-nil.
    ///   - textureCoordinates: Optional per-vertex UVs. Must match `positions.count` if non-nil.
    ///   - indices: Triangle indices into the attribute arrays.
    ///   - label: Optional label propagated to the mesh and its buffers.
    ///   - bufferLayout: Whether attributes are interleaved into one buffer
    ///     or split across separate buffers.
    init(
        device: MTLDevice,
        positions: [SIMD3<Float>],
        normals: [SIMD3<Float>]? = nil,
        textureCoordinates: [SIMD2<Float>]? = nil,
        indices: [UInt32],
        label: String? = nil,
        bufferLayout: BufferLayout = .interleaved
    ) {
        let vertexCount = positions.count
        if let normals { precondition(normals.count == vertexCount, "normals.count must equal positions.count") }
        if let textureCoordinates { precondition(textureCoordinates.count == vertexCount, "textureCoordinates.count must equal positions.count") }

        // Build attribute list matching MetalMesh(mesh:device:)'s ordering.
        var rawAttributes: [(semantic: VertexDescriptor.Attribute.Semantic, format: MTLVertexFormat)] = [
            (.position, .float3)
        ]
        if normals != nil { rawAttributes.append((.normal, .float3)) }
        if textureCoordinates != nil { rawAttributes.append((.texcoord, .float2)) }

        let attributes: [VertexDescriptor.Attribute]
        let layouts: [VertexDescriptor.Layout]

        switch bufferLayout {
        case .interleaved:
            attributes = rawAttributes.map {
                VertexDescriptor.Attribute(semantic: $0.semantic, format: $0.format, offset: 0, bufferIndex: 0)
            }
            layouts = [.init(bufferIndex: 0, stride: 0, stepFunction: .perVertex, stepRate: 1)]

        case .separateBuffers:
            attributes = rawAttributes.enumerated().map { idx, attr in
                VertexDescriptor.Attribute(semantic: attr.semantic, format: attr.format, offset: 0, bufferIndex: idx)
            }
            layouts = rawAttributes.indices.map {
                .init(bufferIndex: $0, stride: 0, stepFunction: .perVertex, stepRate: 1)
            }
        }

        let descriptor = VertexDescriptor(attributes: attributes, layouts: layouts).normalized()

        // Pack vertex data per buffer.
        let bufferIndices = Set(descriptor.attributes.map(\.bufferIndex)).sorted()
        var bufferData: [Int: [UInt8]] = [:]
        for bi in bufferIndices {
            let stride = descriptor.layouts[bi]!.stride
            bufferData[bi] = [UInt8](repeating: 0, count: stride * vertexCount)
        }

        for bi in bufferIndices {
            let stride = descriptor.layouts[bi]!.stride
            bufferData[bi]!.withUnsafeMutableBytes { buf in
                guard let base = buf.baseAddress else { return }
                for attr in descriptor.attributes where attr.bufferIndex == bi {
                    for vi in 0..<vertexCount {
                        let dest = base.advanced(by: vi * stride + attr.offset)
                        switch attr.semantic {
                        case .position:
                            var packed = Packed3<Float>(positions[vi])
                            withUnsafeBytes(of: &packed) { src in
                                dest.copyMemory(from: src.baseAddress!, byteCount: src.count)
                            }

                        case .normal:
                            var packed = Packed3<Float>(normals![vi])
                            withUnsafeBytes(of: &packed) { src in
                                dest.copyMemory(from: src.baseAddress!, byteCount: src.count)
                            }

                        case .texcoord:
                            var uv = textureCoordinates![vi]
                            withUnsafeBytes(of: &uv) { src in
                                dest.copyMemory(from: src.baseAddress!, byteCount: src.count)
                            }

                        default:
                            break
                        }
                    }
                }
            }
        }

        // Allocate vertex buffers.
        var vtxBuffers: [Int: MTLBuffer] = [:]
        for bi in bufferIndices {
            let data = bufferData[bi]!
            let buffer: MTLBuffer
            if data.isEmpty {
                buffer = device.makeBuffer(length: 1, options: [])!
            } else {
                buffer = device.makeBuffer(bytes: data, length: data.count, options: [])!
            }
            buffer.label = label.map { "\($0) Vertices[\(bi)]" }
            vtxBuffers[bi] = buffer
        }

        // Index buffer.
        let indexBuffer = device.makeBuffer(
            bytes: indices,
            length: MemoryLayout<UInt32>.stride * indices.count,
            options: []
        )!
        indexBuffer.label = label.map { "\($0) Indices" }

        self.label = label
        self.vertexBuffers = vtxBuffers
        self.vertexCount = vertexCount
        self.vertexDescriptor = descriptor
        self.submeshes = [
            Submesh(label: nil, indexBuffer: indexBuffer, indexCount: indices.count)
        ]
    }

    /// Create a `MetalMesh` directly from preexisting `MTLBuffer`s and a
    /// matching `VertexDescriptor`, with no copies.
    ///
    /// Use this for zero-copy paths where buffers and a descriptor have
    /// already been produced (e.g. memory-mapped raw blobs from disk).
    ///
    /// The resulting mesh has a single submesh covering all indices. The
    /// caller is responsible for ensuring the buffers, vertex count, index
    /// count, and descriptor are mutually consistent — only cheap shape
    /// checks are performed.
    ///
    /// - Parameters:
    ///   - vertexBuffers: Vertex buffers keyed by buffer index. Must contain a
    ///     buffer for every `bufferIndex` referenced by `vertexDescriptor`.
    ///   - vertexCount: Number of vertices addressable in `vertexBuffers`.
    ///   - vertexDescriptor: Describes the layout and semantics of vertex attributes.
    ///   - indexBuffer: Buffer of `UInt32` triangle indices.
    ///   - indexCount: Number of indices in `indexBuffer`.
    ///   - label: Optional label propagated to the mesh.
    init(
        vertexBuffers: [Int: MTLBuffer],
        vertexCount: Int,
        vertexDescriptor: VertexDescriptor,
        indexBuffer: MTLBuffer,
        indexCount: Int,
        label: String? = nil
    ) {
        for bi in Set(vertexDescriptor.attributes.map(\.bufferIndex)) {
            precondition(vertexBuffers[bi] != nil, "vertexBuffers is missing buffer at index \(bi) referenced by vertexDescriptor")
        }

        self.label = label
        self.vertexBuffers = vertexBuffers
        self.vertexCount = vertexCount
        self.vertexDescriptor = vertexDescriptor
        self.submeshes = [
            Submesh(label: nil, indexBuffer: indexBuffer, indexCount: indexCount)
        ]
    }
}
