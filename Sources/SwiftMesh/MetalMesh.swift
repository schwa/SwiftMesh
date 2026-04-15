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
    public init(mesh: Mesh, device: MTLDevice, label: String? = nil, bufferLayout: BufferLayout = .interleaved) {
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
    /// Produces a triangle-only mesh. Vertices are deduplicated by position,
    /// with per-corner attributes (normals, UVs, etc.) preserved on the
    /// half-edge topology.
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

        // Deduplicate vertices by position
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

        // Collect triangle faces
        var allFaces: [[Int]] = []
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

        // Build per-corner attributes
        let heCount = topology.halfEdges.count
        var normals: [SIMD3<Float>]? = normalAttr != nil ? .init(repeating: .zero, count: heCount) : nil
        var texcoords: [SIMD2<Float>]? = texcoordAttr != nil ? .init(repeating: .zero, count: heCount) : nil
        var tangents: [SIMD3<Float>]? = tangentAttr != nil ? .init(repeating: .zero, count: heCount) : nil
        var bitangents: [SIMD3<Float>]? = bitangentAttr != nil ? .init(repeating: .zero, count: heCount) : nil
        var colors: [SIMD4<Float>]? = colorAttr != nil ? .init(repeating: .zero, count: heCount) : nil

        for (faceIdx, cornerVerts) in allCornerMetalVertices.enumerated() {
            let faceID = HalfEdgeTopology.FaceID(raw: faceIdx)
            let heLoop = topology.halfEdgeLoop(for: faceID)

            for (cornerIdx, heID) in heLoop.enumerated() {
                let metalVertex = cornerVerts[cornerIdx]

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
