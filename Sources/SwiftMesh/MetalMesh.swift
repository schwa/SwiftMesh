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
        public var bounds: BoundingBox?

        /// Creates a submesh over an existing index buffer.
        public init(label: String? = nil, indexBuffer: MTLBuffer, indexBufferOffset: Int = 0, indexCount: Int, indexType: MTLIndexType = .uint32, primitiveType: MTLPrimitiveType = .triangle, bounds: BoundingBox? = nil) {
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
    public var bounds: BoundingBox?
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
    /// Faces are triangulated and corners become vertices (see ``Mesh/vertexArrays()``).
    /// Each `Mesh.Submesh` becomes a `MetalMesh.Submesh`; they share one index buffer.
    /// With `signedTangents`, tangents are `.float4` with the bitangent sign in w and there is no bitangent attribute.
    public init(mesh: Mesh, device: MTLDevice, label: String? = nil, bufferLayout: BufferLayout = .interleaved, preserveTopology: Bool = false, signedTangents: Bool = false) {
        let arrays = mesh.vertexArrays(signedTangents: signedTangents)
        self.init(device: device, attributes: arrays.attributes, submeshes: arrays.submeshes, label: label, bufferLayout: bufferLayout)
        let metalVertexToPosition = arrays.sourceVertices.map { UInt32($0.raw) }

        // Build corner-table topology buffers when requested.
        if preserveTopology {
            // Flatten all submesh indices into a single halfedge array.
            let allIndices: [UInt32] = arrays.submeshes.flatMap(\.indices)
            let halfEdgeCount = allIndices.count
            let positionCount = Int(metalVertexToPosition.max().map { $0 + 1 } ?? 0)

            // Build opposites: hash directed edges by (min(posA, posB), max(posA, posB))
            // to pair up twin half-edges.
            var oppositesArray = [UInt32](repeating: UInt32.max, count: halfEdgeCount)
            // Key: (min, max) position pair → list of half-edge indices with that edge
            var edgeMap: [UInt64: [Int]] = [:]

            for h in 0..<halfEdgeCount {
                let triBase = (h / 3) * 3
                let nextH = triBase + (h + 1) % 3
                let posA = metalVertexToPosition[Int(allIndices[h])]
                let posB = metalVertexToPosition[Int(allIndices[nextH])]
                let lo = min(posA, posB)
                let hi = max(posA, posB)
                let key = UInt64(lo) << 32 | UInt64(hi)
                edgeMap[key, default: []].append(h)
            }

            for (_, halfEdges) in edgeMap {
                if halfEdges.count == 2 {
                    oppositesArray[halfEdges[0]] = UInt32(halfEdges[1])
                    oppositesArray[halfEdges[1]] = UInt32(halfEdges[0])
                }
                // count == 1 → boundary, already UInt32.max
                // count > 2 → non-manifold, leave as UInt32.max
            }

            let oppBuf = device.makeBuffer(bytes: oppositesArray, length: MemoryLayout<UInt32>.stride * halfEdgeCount, options: [])!
            oppBuf.label = label.map { "\($0) Opposites" }
            self.opposites = oppBuf

            // Build vertToHalfedge: one representative outgoing half-edge per position vertex.
            var v2he = [UInt32](repeating: UInt32.max, count: positionCount)
            for h in 0..<halfEdgeCount {
                let posIdx = Int(metalVertexToPosition[Int(allIndices[h])])
                if v2he[posIdx] == UInt32.max {
                    v2he[posIdx] = UInt32(h)
                }
            }

            let v2heBuf = device.makeBuffer(bytes: v2he, length: MemoryLayout<UInt32>.stride * positionCount, options: [])!
            v2heBuf.label = label.map { "\($0) VertToHalfedge" }
            self.vertToHalfedge = v2heBuf
        }
    }
}

// MARK: - Conversion to Mesh

public extension MetalMesh {
    /// Convert a MetalMesh back to a Mesh.
    ///
    /// When ``opposites`` and ``vertToHalfedge`` are present (i.e. the mesh was
    /// created with `preserveTopology: true`), the half-edge topology is rebuilt
    /// with exact twin wiring from the corner table — no information is lost.
    ///
    /// Otherwise, produces a triangle-only mesh with topology rebuilt via
    /// position deduplication (lossy: original twin wiring at seams with
    /// different per-corner attributes may not round-trip exactly).
    func toMesh() -> Mesh {
        // Find attribute info
        struct AttrInfo {
            let semantic: VertexDescriptor.Attribute.Semantic
            let offset: Int
            let bufferIndex: Int
        }

        let attrInfos = vertexDescriptor.attributes.map {
            AttrInfo(semantic: $0.semantic, offset: $0.offset, bufferIndex: $0.bufferIndex)
        }

        func findAttr(_ semantic: VertexDescriptor.Attribute.Semantic) -> AttrInfo? {
            attrInfos.first { $0.semantic == semantic }
        }

        let positionAttr = findAttr(.position)!
        let normalAttr = findAttr(.normal)
        let texcoordAttr = findAttr(.texcoord())
        let tangentAttr = findAttr(.tangent)
        let bitangentAttr = findAttr(.bitangent)
        let colorAttr = findAttr(.color())

        // Buffer pointers and strides
        var bufferPtrs: [Int: UnsafeMutablePointer<UInt8>] = [:]
        var bufferStrides: [Int: Int] = [:]
        for (bi, buffer) in vertexBuffers {
            bufferPtrs[bi] = (buffer.contents() + (vertexBufferOffsets[bi] ?? 0)).assumingMemoryBound(to: UInt8.self)
            bufferStrides[bi] = vertexDescriptor.layouts[bi]!.stride
        }

        // Helpers to read from the correct buffer
        func readFloat3(vertex: Int, attr: AttrInfo) -> SIMD3<Float> {
            let ptr = bufferPtrs[attr.bufferIndex]!.advanced(by: vertex * bufferStrides[attr.bufferIndex]! + attr.offset)
            return ptr.withMemoryRebound(to: Float.self, capacity: 3) { p in
                SIMD3<Float>(p[0], p[1], p[2])
            }
        }

        func readFloat2(vertex: Int, attr: AttrInfo) -> SIMD2<Float> {
            let ptr = bufferPtrs[attr.bufferIndex]!.advanced(by: vertex * bufferStrides[attr.bufferIndex]! + attr.offset)
            return ptr.withMemoryRebound(to: Float.self, capacity: 2) { p in
                SIMD2<Float>(p[0], p[1])
            }
        }

        func readFloat4(vertex: Int, attr: AttrInfo) -> SIMD4<Float> {
            let ptr = bufferPtrs[attr.bufferIndex]!.advanced(by: vertex * bufferStrides[attr.bufferIndex]! + attr.offset)
            return ptr.withMemoryRebound(to: Float.self, capacity: 4) { p in
                SIMD4<Float>(p[0], p[1], p[2], p[3])
            }
        }

        // Deduplicate Metal vertices by position to get unique position list.
        var uniquePositions: [SIMD3<Float>] = []
        var positionMap: [Int: Int] = [:]
        var positionDedup: [SIMD3<Float>: Int] = [:]

        for vi in 0..<vertexCount {
            let pos = readFloat3(vertex: vi, attr: positionAttr)
            if let existing = positionDedup[pos] {
                positionMap[vi] = existing
            } else {
                let idx = uniquePositions.count
                uniquePositions.append(pos)
                positionDedup[pos] = idx
                positionMap[vi] = idx
            }
        }

        // Flatten all submesh indices and track submesh face ranges.
        var allIndices: [UInt32] = []
        var submeshFaceRanges: [(label: String?, start: Int, count: Int)] = []

        for submesh in submeshes {
            let triCount = submesh.indexCount / 3
            let start = allIndices.count / 3
            precondition(submesh.primitiveType == .triangle, "Converting MetalMesh to Mesh requires triangle submeshes")
            allIndices.append(contentsOf: submesh.indices)
            submeshFaceRanges.append((label: submesh.label, start: start, count: triCount))
        }

        let triCount = allIndices.count / 3
        let halfEdgeCount = allIndices.count

        // Build topology — exact path when corner-table buffers are present,
        // fallback to position-dedup reconstruction otherwise.
        let topology: HalfEdgeTopology
        if let oppBuf = opposites {
            let oppPtr = oppBuf.contents().assumingMemoryBound(to: UInt32.self)
            let sentinel = UInt32.max

            typealias VID = HalfEdgeTopology.VertexID
            typealias HEID = HalfEdgeTopology.HalfEdgeID
            typealias FID = HalfEdgeTopology.FaceID

            // Vertices
            var vertices = (0..<uniquePositions.count).map {
                HalfEdgeTopology.Vertex(id: VID(raw: $0), edge: nil)
            }

            // Half-edges: one per index entry. h belongs to face h/3.
            var halfEdges = [HalfEdgeTopology.HalfEdge]()
            halfEdges.reserveCapacity(halfEdgeCount)

            for h in 0..<halfEdgeCount {
                let faceIdx = h / 3
                let posIdx = positionMap[Int(allIndices[h])]!
                let triBase = (h / 3) * 3
                let nextH = triBase + (h + 1) % 3
                let prevH = triBase + (h + 2) % 3
                let opp = oppPtr[h]
                let twin: HEID? = opp != sentinel ? HEID(raw: Int(opp)) : nil

                halfEdges.append(HalfEdgeTopology.HalfEdge(
                    id: HEID(raw: h),
                    origin: VID(raw: posIdx),
                    twin: twin,
                    next: HEID(raw: nextH),
                    prev: HEID(raw: prevH),
                    face: FID(raw: faceIdx)
                ))

                if vertices[posIdx].edge == nil {
                    vertices[posIdx].edge = HEID(raw: h)
                }
            }

            // Faces
            var faces = [HalfEdgeTopology.Face]()
            faces.reserveCapacity(triCount)
            for f in 0..<triCount {
                faces.append(HalfEdgeTopology.Face(
                    id: FID(raw: f),
                    edge: HEID(raw: f * 3),
                    holeEdges: []
                ))
            }

            var topo = HalfEdgeTopology()
            topo.vertices = vertices
            topo.halfEdges = halfEdges
            topo.faces = faces
            topology = topo
        } else {
            // Fallback: rebuild topology from position-deduped face definitions.
            let faceDefs = (0..<triCount).map { tri -> HalfEdgeTopology.FaceDefinition in
                let i0 = positionMap[Int(allIndices[tri * 3])]!
                let i1 = positionMap[Int(allIndices[tri * 3 + 1])]!
                let i2 = positionMap[Int(allIndices[tri * 3 + 2])]!
                return .init(outer: [i0, i1, i2])
            }
            topology = HalfEdgeTopology(vertexCount: uniquePositions.count, faces: faceDefs)
        }

        // Build per-corner attributes
        let heCount = topology.halfEdges.count
        var normals: [SIMD3<Float>]? = normalAttr != nil ? .init(repeating: .zero, count: heCount) : nil
        var texcoords: [SIMD2<Float>]? = texcoordAttr != nil ? .init(repeating: .zero, count: heCount) : nil
        var tangents: [SIMD3<Float>]? = tangentAttr != nil ? .init(repeating: .zero, count: heCount) : nil
        var bitangents: [SIMD3<Float>]? = bitangentAttr != nil ? .init(repeating: .zero, count: heCount) : nil
        var colors: [SIMD4<Float>]? = colorAttr != nil ? .init(repeating: .zero, count: heCount) : nil

        for tri in 0..<triCount {
            let faceID = HalfEdgeTopology.FaceID(raw: tri)
            let heLoop = topology.halfEdgeLoop(for: faceID)

            for (cornerIdx, heID) in heLoop.enumerated() {
                let metalVertex = Int(allIndices[tri * 3 + cornerIdx])

                if let attr = normalAttr {
                    normals![heID.raw] = readFloat3(vertex: metalVertex, attr: attr)
                }
                if let attr = texcoordAttr {
                    texcoords![heID.raw] = readFloat2(vertex: metalVertex, attr: attr)
                }
                if let attr = tangentAttr {
                    tangents![heID.raw] = readFloat3(vertex: metalVertex, attr: attr)
                }
                if let attr = bitangentAttr {
                    bitangents![heID.raw] = readFloat3(vertex: metalVertex, attr: attr)
                }
                if let attr = colorAttr {
                    colors![heID.raw] = readFloat4(vertex: metalVertex, attr: attr)
                }
            }
        }

        let meshSubmeshes = submeshFaceRanges.map { range in
            let faceIDs = (range.start..<(range.start + range.count)).map { HalfEdgeTopology.FaceID(raw: $0) }
            return Mesh.Submesh(label: range.label, faces: faceIDs)
        }

        return Mesh(
            topology: topology,
            positions: uniquePositions,
            normals: normals,
            textureCoordinates: texcoords,
            tangents: tangents,
            bitangents: bitangents,
            colors: colors,
            submeshes: meshSubmeshes
        )
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
