import GeometryLite3D
import Metal
import MetalSupport
import simd

/// A GPU-ready mesh produced from a `Mesh` by triangulating faces,
/// and interleaving attributes into Metal buffers.
///
/// Vertices with identical positions and per-corner attributes are shared in
/// the output buffer, so downstream consumers (e.g. wireframe edge extraction)
/// can deduplicate edges by comparing index values.
///
/// Faces are triangulated via earcut for n-gons, or passed through for triangles.
public struct MetalMesh {
    public struct Submesh {
        public var label: String?
        public var indexBuffer: MTLBuffer
        public var indexCount: Int
    }

    public var label: String?
    public var vertexBuffer: MTLBuffer
    public var vertexCount: Int
    public var vertexDescriptor: VertexDescriptor
    public var submeshes: [Submesh]

    /// Create a MetalMesh from a Mesh.
    ///
    /// Each half-edge corner becomes a unique vertex in the output buffer.
    /// Each `Mesh.Submesh` becomes a `MetalMesh.Submesh` with its own index buffer.
    public init(mesh: Mesh, device: MTLDevice, label: String? = nil) {
        self.label = label

        // Build vertex descriptor based on available attributes
        var attributes: [VertexDescriptor.Attribute] = [
            .init(semantic: .position, format: .float3, offset: 0, bufferIndex: 0)
        ]
        if mesh.normals != nil {
            attributes.append(.init(semantic: .normal, format: .float3, offset: 0, bufferIndex: 0))
        }
        if mesh.textureCoordinates != nil {
            attributes.append(.init(semantic: .texcoord, format: .float2, offset: 0, bufferIndex: 0))
        }
        if mesh.tangents != nil {
            attributes.append(.init(semantic: .tangent, format: .float3, offset: 0, bufferIndex: 0))
        }
        if mesh.bitangents != nil {
            attributes.append(.init(semantic: .bitangent, format: .float3, offset: 0, bufferIndex: 0))
        }
        if mesh.colors != nil {
            attributes.append(.init(semantic: .color, format: .float4, offset: 0, bufferIndex: 0))
        }

        let descriptor = VertexDescriptor(
            attributes: attributes,
            layouts: [.init(bufferIndex: 0, stride: 0, stepFunction: .perVertex, stepRate: 1)]
        ).normalized()

        self.vertexDescriptor = descriptor

        let stride = descriptor.layouts[0]!.stride

        // Walk submeshes to build interleaved vertex data and per-submesh index arrays.
        // Vertices with identical byte content are deduplicated so that shared edges
        // reference the same index.
        var vertexData = [UInt8]()
        var currentVertexIndex: UInt32 = 0
        var builtSubmeshes: [(label: String?, indices: [UInt32])] = []
        var vertexDedup: [ArraySlice<UInt8>: UInt32] = [:]

        for submesh in mesh.submeshes {
            var indices: [UInt32] = []

            for faceID in submesh.faces {
                // Triangulate the face
                let vertexIDs = mesh.topology.vertexLoop(for: faceID)
                let faceTriangles: [(HalfEdgeTopology.VertexID, HalfEdgeTopology.VertexID, HalfEdgeTopology.VertexID)]
                if vertexIDs.count == 3 {
                    faceTriangles = [(vertexIDs[0], vertexIDs[1], vertexIDs[2])]
                } else {
                    faceTriangles = mesh.triangulateFace(vertexIDs: vertexIDs)
                }

                // Build a lookup from vertexID to half-edge ID for this face
                // (for per-corner attribute lookup)
                let heLoop = mesh.topology.halfEdgeLoop(for: faceID)
                var vertexToHE: [Int: HalfEdgeTopology.HalfEdgeID] = [:]
                for heID in heLoop {
                    vertexToHE[mesh.topology.halfEdges[heID.raw].origin.raw] = heID
                }

                for (vid0, vid1, vid2) in faceTriangles {
                    for vertexID in [vid0, vid1, vid2] {
                        let heID = vertexToHE[vertexID.raw]

                        var vertexBytes = [UInt8](repeating: 0, count: stride)
                        vertexBytes.withUnsafeMutableBytes { bytes in
                            guard let base = bytes.baseAddress else {
                                return
                            }
                            for attr in descriptor.attributes where attr.bufferIndex == 0 {
                                let dest = base.advanced(by: attr.offset)
                                switch attr.semantic {
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

                        // Deduplicate: reuse existing vertex if bytes match
                        let slice = vertexBytes[...]
                        if let existingIndex = vertexDedup[slice] {
                            indices.append(existingIndex)
                        } else {
                            vertexDedup[slice] = currentVertexIndex
                            vertexData.append(contentsOf: vertexBytes)
                            indices.append(currentVertexIndex)
                            currentVertexIndex += 1
                        }
                    }
                }
            }

            builtSubmeshes.append((label: submesh.label, indices: indices))
        }

        self.vertexCount = Int(currentVertexIndex)

        // Create vertex buffer
        let vtxBuffer: MTLBuffer
        if vertexData.isEmpty {
            vtxBuffer = device.makeBuffer(length: 1, options: [])!
        } else {
            vtxBuffer = device.makeBuffer(bytes: vertexData, length: vertexData.count, options: [])!
        }
        vtxBuffer.label = label.map { "\($0) Vertices" }
        self.vertexBuffer = vtxBuffer

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
    }
}

// MARK: - Conversion to Mesh

public extension MetalMesh {
    /// Convert a MetalMesh back to a Mesh.
    ///
    /// Produces a triangle-only mesh. Vertices are deduplicated by position,
    /// with per-corner attributes (normals, UVs, etc.) preserved on the
    /// half-edge topology.
    func toMesh() -> Mesh {
        let stride = vertexDescriptor.layouts[0]!.stride

        // Find attribute offsets
        func attributeOffset(for semantic: VertexDescriptor.Attribute.Semantic) -> Int? {
            vertexDescriptor.attributes.first(where: { $0.semantic == semantic && $0.bufferIndex == 0 })?.offset
        }

        let positionOffset = attributeOffset(for: .position)!
        let normalOffset = attributeOffset(for: .normal)
        let texcoordOffset = attributeOffset(for: .texcoord)
        let tangentOffset = attributeOffset(for: .tangent)
        let bitangentOffset = attributeOffset(for: .bitangent)
        let colorOffset = attributeOffset(for: .color)

        // Read vertex data from buffer
        let vertexPtr = vertexBuffer.contents().assumingMemoryBound(to: UInt8.self)

        // Helper to read typed data from a vertex
        func readFloat3(vertex: Int, offset: Int) -> SIMD3<Float> {
            let ptr = vertexPtr.advanced(by: vertex * stride + offset)
            let x = ptr.withMemoryRebound(to: Float.self, capacity: 3) { p in
                SIMD3<Float>(p[0], p[1], p[2])
            }
            return x
        }

        func readFloat2(vertex: Int, offset: Int) -> SIMD2<Float> {
            let ptr = vertexPtr.advanced(by: vertex * stride + offset)
            let x = ptr.withMemoryRebound(to: Float.self, capacity: 2) { p in
                SIMD2<Float>(p[0], p[1])
            }
            return x
        }

        func readFloat4(vertex: Int, offset: Int) -> SIMD4<Float> {
            let ptr = vertexPtr.advanced(by: vertex * stride + offset)
            let x = ptr.withMemoryRebound(to: Float.self, capacity: 4) { p in
                SIMD4<Float>(p[0], p[1], p[2], p[3])
            }
            return x
        }

        // Deduplicate vertices by position → assign position indices
        // Two MetalMesh vertices with the same position but different normals
        // map to the same Mesh vertex (position is per-vertex, normals are per-corner).
        var uniquePositions: [SIMD3<Float>] = []
        var positionMap: [Int: Int] = [:] // metalVertex → position index
        var positionDedup: [SIMD3<Float>: Int] = [:]

        // We need a tolerance-based comparison for positions
        for vi in 0..<vertexCount {
            let pos = readFloat3(vertex: vi, offset: positionOffset)
            if let existing = positionDedup[pos] {
                positionMap[vi] = existing
            } else {
                let idx = uniquePositions.count
                uniquePositions.append(pos)
                positionDedup[pos] = idx
                positionMap[vi] = idx
            }
        }

        // Collect all triangle faces across submeshes, remapped to position indices
        var allFaces: [[Int]] = []
        // Keep track of the original metal vertex indices per corner for attribute lookup
        var allCornerMetalVertices: [[Int]] = []
        var submeshFaceRanges: [(label: String?, start: Int, count: Int)] = []

        for submesh in submeshes {
            let start = allFaces.count
            let indexPtr = submesh.indexBuffer.contents().assumingMemoryBound(to: UInt32.self)
            let triCount = submesh.indexCount / 3
            for tri in 0..<triCount {
                let i0 = Int(indexPtr[tri * 3])
                let i1 = Int(indexPtr[tri * 3 + 1])
                let i2 = Int(indexPtr[tri * 3 + 2])
                allFaces.append([positionMap[i0]!, positionMap[i1]!, positionMap[i2]!])
                allCornerMetalVertices.append([i0, i1, i2])
            }
            submeshFaceRanges.append((label: submesh.label, start: start, count: allFaces.count - start))
        }

        // Build topology
        let faceDefs = allFaces.map { HalfEdgeTopology.FaceDefinition(outer: $0) }
        let topology = HalfEdgeTopology(vertexCount: uniquePositions.count, faces: faceDefs)

        // Build per-corner attributes indexed by HalfEdgeID.raw
        let heCount = topology.halfEdges.count
        var normals: [SIMD3<Float>]? = normalOffset != nil ? .init(repeating: .zero, count: heCount) : nil
        var texcoords: [SIMD2<Float>]? = texcoordOffset != nil ? .init(repeating: .zero, count: heCount) : nil
        var tangents: [SIMD3<Float>]? = tangentOffset != nil ? .init(repeating: .zero, count: heCount) : nil
        var bitangents: [SIMD3<Float>]? = bitangentOffset != nil ? .init(repeating: .zero, count: heCount) : nil
        var colors: [SIMD4<Float>]? = colorOffset != nil ? .init(repeating: .zero, count: heCount) : nil

        // Walk faces and assign per-corner attributes
        for (faceIdx, cornerVerts) in allCornerMetalVertices.enumerated() {
            let faceID = HalfEdgeTopology.FaceID(raw: faceIdx)
            let heLoop = topology.halfEdgeLoop(for: faceID)

            for (cornerIdx, heID) in heLoop.enumerated() {
                let metalVertex = cornerVerts[cornerIdx]

                if let offset = normalOffset {
                    normals![heID.raw] = readFloat3(vertex: metalVertex, offset: offset)
                }
                if let offset = texcoordOffset {
                    texcoords![heID.raw] = readFloat2(vertex: metalVertex, offset: offset)
                }
                if let offset = tangentOffset {
                    tangents![heID.raw] = readFloat3(vertex: metalVertex, offset: offset)
                }
                if let offset = bitangentOffset {
                    bitangents![heID.raw] = readFloat3(vertex: metalVertex, offset: offset)
                }
                if let offset = colorOffset {
                    colors![heID.raw] = readFloat4(vertex: metalVertex, offset: offset)
                }
            }
        }

        // Build submeshes
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
        setVertexBuffer(metalMesh.vertexBuffer, offset: 0, index: 0)
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
