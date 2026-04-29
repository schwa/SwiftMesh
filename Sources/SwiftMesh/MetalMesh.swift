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
/// Faces are triangulated via earcut for n-gons, or passed through for triangles.
public struct MetalMesh {
    /// A group of triangles within a ``MetalMesh`` sharing the same material.
    public struct Submesh {
        /// An optional human-readable name for the submesh.
        public var label: String?
        /// The Metal buffer containing triangle indices (`UInt32`).
        public var indexBuffer: MTLBuffer
        /// The number of indices in ``indexBuffer``.
        public var indexCount: Int
    }

    /// Controls how vertex attributes are packed into Metal buffers.
    public enum BufferLayout {
        /// All attributes interleaved into a single buffer (buffer index 0).
        case interleaved
        /// Each attribute in its own buffer (buffer indices 0, 1, 2, …).
        case separateBuffers
    }

    /// An optional human-readable name for the mesh.
    public var label: String?
    /// Vertex buffers keyed by buffer index.
    public var vertexBuffers: [Int: MTLBuffer]
    /// The number of vertices across all buffers.
    public var vertexCount: Int
    /// Describes the layout and semantics of vertex attributes.
    public var vertexDescriptor: VertexDescriptor
    /// The triangle groups that make up the mesh.
    public var submeshes: [Submesh]

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
    /// Each half-edge corner becomes a unique vertex in the output buffer(s).
    /// Each `Mesh.Submesh` becomes a `MetalMesh.Submesh` with its own index buffer.
    public init(mesh: Mesh, device: MTLDevice, label: String? = nil, bufferLayout: BufferLayout = .interleaved, preserveTopology: Bool = false) {
        self.label = label

        // Build attribute list based on available mesh data
        var rawAttributes: [(semantic: VertexDescriptor.Attribute.Semantic, format: MTLVertexFormat)] = [
            (.position, .float3)
        ]
        if mesh.normals != nil { rawAttributes.append((.normal, .float3)) }
        if mesh.textureCoordinates != nil { rawAttributes.append((.texcoord, .float2)) }
        if mesh.tangents != nil { rawAttributes.append((.tangent, .float3)) }
        if mesh.bitangents != nil { rawAttributes.append((.bitangent, .float3)) }
        if mesh.colors != nil { rawAttributes.append((.color, .float4)) }

        // Assign buffer indices based on layout
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
        self.vertexDescriptor = descriptor

        // Collect buffer indices we need to write to
        let bufferIndices = Set(descriptor.attributes.map(\.bufferIndex)).sorted()

        // Walk submeshes to build vertex data and per-submesh index arrays.
        // For interleaved: dedup by full vertex bytes across all attributes.
        // For separate: dedup by concatenated attribute bytes (same vertex index across all buffers).
        var bufferData: [Int: [UInt8]] = [:]
        for bi in bufferIndices { bufferData[bi] = [] }

        var currentVertexIndex: UInt32 = 0
        var builtSubmeshes: [(label: String?, indices: [UInt32])] = []

        // For dedup, we build a composite key from all attribute bytes
        var vertexDedup: [[UInt8]: UInt32] = [:]

        // Map Metal vertex index → position vertex index (for topology building)
        var metalVertexToPosition: [UInt32] = []

        for submesh in mesh.submeshes {
            var indices: [UInt32] = []

            for faceID in submesh.faces {
                let vertexIDs = mesh.topology.vertexLoop(for: faceID)
                let faceTriangles: [(HalfEdgeTopology.VertexID, HalfEdgeTopology.VertexID, HalfEdgeTopology.VertexID)]
                if vertexIDs.count == 3 {
                    faceTriangles = [(vertexIDs[0], vertexIDs[1], vertexIDs[2])]
                } else {
                    faceTriangles = mesh.triangulateFace(vertexIDs: vertexIDs)
                }

                let heLoop = mesh.topology.halfEdgeLoop(for: faceID)
                var vertexToHE: [Int: HalfEdgeTopology.HalfEdgeID] = [:]
                for heID in heLoop {
                    vertexToHE[mesh.topology.halfEdges[heID.raw].origin.raw] = heID
                }

                for (vid0, vid1, vid2) in faceTriangles {
                    for vertexID in [vid0, vid1, vid2] {
                        let heID = vertexToHE[vertexID.raw]

                        // Build per-buffer vertex bytes and a composite dedup key
                        var perBuffer: [Int: [UInt8]] = [:]
                        var compositeKey: [UInt8] = []

                        for bi in bufferIndices {
                            let biStride = descriptor.layouts[bi]!.stride
                            var bytes = [UInt8](repeating: 0, count: biStride)
                            bytes.withUnsafeMutableBytes { buf in
                                guard let base = buf.baseAddress else { return }
                                for attr in descriptor.attributes where attr.bufferIndex == bi {
                                    let dest = base.advanced(by: attr.offset)
                                    Self.writeAttribute(attr.semantic, dest: dest, vertexID: vertexID, heID: heID, mesh: mesh)
                                }
                            }
                            perBuffer[bi] = bytes
                            compositeKey.append(contentsOf: bytes)
                        }

                        if let existingIndex = vertexDedup[compositeKey] {
                            indices.append(existingIndex)
                        } else {
                            vertexDedup[compositeKey] = currentVertexIndex
                            for bi in bufferIndices {
                                bufferData[bi]!.append(contentsOf: perBuffer[bi]!)
                            }
                            metalVertexToPosition.append(UInt32(vertexID.raw))
                            indices.append(currentVertexIndex)
                            currentVertexIndex += 1
                        }
                    }
                }
            }

            builtSubmeshes.append((label: submesh.label, indices: indices))
        }

        self.vertexCount = Int(currentVertexIndex)

        // Create vertex buffers
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
        self.vertexBuffers = vtxBuffers

        // Create submeshes
        self.submeshes = builtSubmeshes.map { sub in
            let idxBuffer = device.makeBuffer(
                bytes: sub.indices,
                length: MemoryLayout<UInt32>.stride * sub.indices.count,
                options: []
            )!
            idxBuffer.label = sub.label ?? label.map { "\($0) Indices" }
            return Submesh(
                label: sub.label,
                indexBuffer: idxBuffer,
                indexCount: sub.indices.count
            )
        }

        // Build corner-table topology buffers when requested.
        if preserveTopology {
            // Flatten all submesh indices into a single halfedge array.
            let allIndices: [UInt32] = builtSubmeshes.flatMap(\.indices)
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

    /// Write a single attribute value into a destination pointer.
    private static func writeAttribute(
        _ semantic: VertexDescriptor.Attribute.Semantic,
        dest: UnsafeMutableRawPointer,
        vertexID: HalfEdgeTopology.VertexID,
        heID: HalfEdgeTopology.HalfEdgeID?,
        mesh: Mesh
    ) {
        switch semantic {
        case .position:
            var packed = Packed3<Float>(mesh.positions[vertexID.raw])
            withUnsafeBytes(of: &packed) { src in
                dest.copyMemory(from: src.baseAddress!, byteCount: src.count)
            }

        case .normal:
            if let normals = mesh.normals, let heID {
                var packed = Packed3<Float>(normals[heID.raw])
                withUnsafeBytes(of: &packed) { src in
                    dest.copyMemory(from: src.baseAddress!, byteCount: src.count)
                }
            }

        case .texcoord:
            if let uvs = mesh.textureCoordinates, let heID {
                var uv = uvs[heID.raw]
                withUnsafeBytes(of: &uv) { src in
                    dest.copyMemory(from: src.baseAddress!, byteCount: src.count)
                }
            }

        case .tangent:
            if let tangents = mesh.tangents, let heID {
                var packed = Packed3<Float>(tangents[heID.raw])
                withUnsafeBytes(of: &packed) { src in
                    dest.copyMemory(from: src.baseAddress!, byteCount: src.count)
                }
            }

        case .bitangent:
            if let bitangents = mesh.bitangents, let heID {
                var packed = Packed3<Float>(bitangents[heID.raw])
                withUnsafeBytes(of: &packed) { src in
                    dest.copyMemory(from: src.baseAddress!, byteCount: src.count)
                }
            }

        case .color:
            if let colors = mesh.colors, let heID {
                var color = colors[heID.raw]
                withUnsafeBytes(of: &color) { src in
                    dest.copyMemory(from: src.baseAddress!, byteCount: src.count)
                }
            }

        default:
            break
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
        let texcoordAttr = findAttr(.texcoord)
        let tangentAttr = findAttr(.tangent)
        let bitangentAttr = findAttr(.bitangent)
        let colorAttr = findAttr(.color)

        // Buffer pointers and strides
        var bufferPtrs: [Int: UnsafeMutablePointer<UInt8>] = [:]
        var bufferStrides: [Int: Int] = [:]
        for (bi, buffer) in vertexBuffers {
            bufferPtrs[bi] = buffer.contents().assumingMemoryBound(to: UInt8.self)
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
            let indexPtr = submesh.indexBuffer.contents().assumingMemoryBound(to: UInt32.self)
            for i in 0..<submesh.indexCount {
                allIndices.append(indexPtr[i])
            }
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
    func draw(_ metalMesh: MetalMesh) {
        for (bufferIndex, buffer) in metalMesh.vertexBuffers {
            setVertexBuffer(buffer, offset: 0, index: bufferIndex)
        }
        for submesh in metalMesh.submeshes {
            drawIndexedPrimitives(
                type: .triangle,
                indexCount: submesh.indexCount,
                indexType: .uint32,
                indexBuffer: submesh.indexBuffer,
                indexBufferOffset: 0
            )
        }
    }
}
