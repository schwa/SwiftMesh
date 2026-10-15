import GeometryLite3D
import Metal
import MetalSupport
import simd

/// A GPU-ready mesh produced from a `Mesh` by triangulating faces,
/// and packing attributes into Metal buffers.
///
/// Vertices with identical positions and per-corner attributes are shared in
/// the output buffer(s), so downstream consumers (e.g. wireframe edge extraction)
/// can deduplicate edges by comparing index values.
///
/// N-gons and faces with holes are triangulated with ``Mesh/triangulatedCorners(of:)``; triangles pass through.
public struct MetalMesh {
    /// A group of triangles within a ``MetalMesh`` sharing the same material.
    public struct Submesh {
        /// An optional human-readable name for the submesh.
        public var label: String?
        /// The Metal buffer containing indices of type ``indexType``.
        public var indexBuffer: MTLBuffer
        /// The number of indices in ``indexBuffer``.
        public var indexCount: Int
        /// Byte offset of the first index in ``indexBuffer``. Buffers may be shared between submeshes.
        public var indexBufferOffset: Int
        /// The index element size. Meshes built from a ``Mesh`` use `.uint32`.
        public var indexType: MTLIndexType
        /// How indices assemble into primitives. Converting back to ``Mesh`` requires `.triangle`.
        public var primitiveType: MTLPrimitiveType
        /// Bounds of the vertices this submesh references, or nil if unknown.
        public var bounds: BoundingBox3D?

        /// Creates a submesh over an existing index buffer.
        public init(label: String? = nil, indexBuffer: MTLBuffer, indexBufferOffset: Int = 0, indexCount: Int, indexType: MTLIndexType = .uint32, primitiveType: MTLPrimitiveType = .triangle, bounds: BoundingBox3D? = nil) {
            self.label = label
            self.indexBuffer = indexBuffer
            self.indexBufferOffset = indexBufferOffset
            self.indexCount = indexCount
            self.indexType = indexType
            self.primitiveType = primitiveType
            self.bounds = bounds
        }

        /// Size of the index data in bytes.
        public var indexByteCount: Int {
            indexCount * (indexType == .uint16 ? 2 : 4)
        }

        /// The indices widened to `UInt32`.
        public var indices: [UInt32] {
            switch indexType {
            case .uint16:
                let pointer = (indexBuffer.contents() + indexBufferOffset).assumingMemoryBound(to: UInt16.self)
                return (0..<indexCount).map { UInt32(pointer[$0]) }

            default:
                let pointer = (indexBuffer.contents() + indexBufferOffset).assumingMemoryBound(to: UInt32.self)
                return Array(UnsafeBufferPointer(start: pointer, count: indexCount))
            }
        }
    }

    /// Controls how vertex attributes are packed into Metal buffers.
    public enum BufferLayout: Sendable {
        /// All attributes interleaved into a single buffer (buffer index 0).
        case interleaved
        /// Each attribute in its own buffer (buffer indices 0, 1, 2, …).
        case separateBuffers
    }

    /// An optional human-readable name for the mesh.
    public var label: String?
    /// Vertex buffers keyed by buffer index.
    public var vertexBuffers: [Int: MTLBuffer]
    /// Byte offset of the first vertex in each buffer, keyed by buffer index. Missing keys mean 0.
    ///
    /// Non-zero when buffers are sub-allocated, as `MTKMeshBufferAllocator` may do.
    public var vertexBufferOffsets: [Int: Int] = [:]
    /// The number of vertices across all buffers.
    public var vertexCount: Int
    /// Describes the layout and semantics of vertex attributes.
    public var vertexDescriptor: VertexDescriptor
    /// The triangle groups that make up the mesh.
    public var submeshes: [Submesh]
    /// Bounds of all vertices, or nil if unknown.
    public var bounds: BoundingBox3D?
    /// Morph targets for the vertices, or nil if the mesh has none.
    public var morphTargets: MorphTargets?
    /// Skin binding data for the joint index and weight attributes, or nil if the mesh is not skinned.
    public var skin: Skin?

    /// Corner-table opposites buffer (`UInt32`, length = total index count across all submeshes).
    ///
    /// `opposites[h]` is the twin half-edge of half-edge `h`, or `UInt32.max` for boundary edges.
    /// Half-edge `h` belongs to face `h/3`, points at vertex `indices[h]`, and its next is
    /// `(h/3)*3 + (h+1)%3`.
    ///
    /// Present only when the mesh was created with `preserveTopology: true`.
    public var opposites: MTLBuffer?

    /// Per-vertex representative half-edge buffer (`UInt32`, length = `vertexCount`).
    ///
    /// `vertToHalfedge[v]` is any outgoing half-edge from vertex `v`. Walk the one-ring
    /// via twin/next from there.
    ///
    /// Present only when the mesh was created with `preserveTopology: true`.
    public var vertToHalfedge: MTLBuffer?

    /// The primary vertex buffer (buffer index 0).
    ///
    /// Convenience accessor for interleaved layouts. Equivalent to `vertexBuffers[0]!`.
    public var vertexBuffer: MTLBuffer {
        guard let buffer = vertexBuffers[0] else {
            fatalError("MetalMesh has no vertex buffer at index 0")
        }
        return buffer
    }

    /// Create a MetalMesh from a Mesh.
    ///
    /// Faces are triangulated and corners become vertices (see ``Mesh/vertexArrays(signedTangents:)``).
    /// Each `Mesh.Submesh` becomes a `MetalMesh.Submesh`; they share one index buffer.
    /// With `signedTangents`, tangents are `.float4` with the bitangent sign in w and there is no bitangent attribute.
    public init(mesh: Mesh, device: MTLDevice, label: String? = nil, bufferLayout: BufferLayout = .interleaved, preserveTopology: Bool = false, signedTangents: Bool = false) {
        let arrays = mesh.vertexArrays(signedTangents: signedTangents)
        self.init(device: device, attributes: arrays.attributes, submeshes: arrays.submeshes, label: label, bufferLayout: bufferLayout)
        if preserveTopology {
            let table = arrays.cornerTable()
            func upload(_ values: [UInt32], _ name: String) -> MTLBuffer {
                let buffer = device.makeBuffer(bytes: values, length: max(1, MemoryLayout<UInt32>.stride * values.count), options: [])!
                buffer.label = label.map { "\($0) \(name)" }
                return buffer
            }
            self.opposites = upload(table.opposites, "Opposites")
            self.vertToHalfedge = upload(table.vertexToHalfEdge, "VertToHalfedge")
        }
    }
}

// MARK: - Conversion to Mesh

public extension Mesh {
    /// Convert a MetalMesh back to a Mesh.
    ///
    /// When ``opposites`` and ``vertToHalfedge`` are present (i.e. the mesh was
    /// created with `preserveTopology: true`), the half-edge topology is rebuilt
    /// with exact twin wiring from the corner table — no information is lost.
    ///
    /// Otherwise, produces a triangle-only mesh with topology rebuilt via
    /// position deduplication (lossy: original twin wiring at seams with
    /// different per-corner attributes may not round-trip exactly).
    init(metalMesh: MetalMesh) {
        let opposites = metalMesh.opposites.map { buffer in
            let count = metalMesh.submeshes.reduce(0) { $0 + $1.indexCount }
            return Array(UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: UInt32.self), count: count))
        }
        self.init(vertexArrays: metalMesh.vertexArrays(), opposites: opposites)
    }
}

// MARK: - Drawing

public extension MTLRenderCommandEncoder {
    /// Binds the mesh's vertex buffers at their buffer indices and draws every submesh.
    ///
    /// The pipeline's vertex descriptor must match `metalMesh.vertexDescriptor`.
    func draw(_ metalMesh: MetalMesh) {
        for (bufferIndex, buffer) in metalMesh.vertexBuffers {
            setVertexBuffer(buffer, offset: metalMesh.vertexBufferOffsets[bufferIndex] ?? 0, index: bufferIndex)
        }
        for submesh in metalMesh.submeshes {
            drawIndexedPrimitives(
                type: submesh.primitiveType,
                indexCount: submesh.indexCount,
                indexType: submesh.indexType,
                indexBuffer: submesh.indexBuffer,
                indexBufferOffset: submesh.indexBufferOffset
            )
        }
    }
}
