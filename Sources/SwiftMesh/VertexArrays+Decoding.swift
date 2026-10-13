import Metal
import MetalSupport
import simd

// CPU side of MetalMesh → Mesh. Only `MetalMesh.vertexArrays()` touches GPU buffers.

public extension MetalMesh.VertexAttributeData {
    /// The values unpacked into `Element`. Bytes beyond `format.size` are zero, so a `.float3`
    /// attribute reads as `SIMD4<Float>` with w = 0, and a `.float4` one as `SIMD3<Float>` drops w.
    func values<Element: SIMD>(as _: Element.Type = Element.self) -> [Element] where Element.Scalar == Float {
        let size = min(format.size, MemoryLayout<Element.Scalar>.stride * Element.scalarCount)
        return bytes.withUnsafeBytes { source in
            (0..<count).map { index in
                var value = Element()
                withUnsafeMutableBytes(of: &value) { destination in
                    destination.baseAddress!.copyMemory(from: source.baseAddress! + index * format.size, byteCount: size)
                }
                return value
            }
        }
    }
}

public extension Mesh.VertexArrays {
    /// Corner-table topology over the concatenated submesh indices; see ``MetalMesh/opposites``.
    ///
    /// Half-edges pair up when their source vertices match. Boundary and non-manifold edges get `UInt32.max`.
    func cornerTable() -> (opposites: [UInt32], vertexToHalfEdge: [UInt32]) {
        let indices = submeshes.flatMap(\.indices)
        let source = sourceVertices.map { UInt32($0.raw) }
        var opposites = [UInt32](repeating: .max, count: indices.count)
        var edges: [UInt64: [Int]] = [:]
        for halfEdge in indices.indices {
            let next = (halfEdge / 3) * 3 + (halfEdge + 1) % 3
            let a = source[Int(indices[halfEdge])]
            let b = source[Int(indices[next])]
            edges[UInt64(min(a, b)) << 32 | UInt64(max(a, b)), default: []].append(halfEdge)
        }
        for pair in edges.values where pair.count == 2 {
            opposites[pair[0]] = UInt32(pair[1])
            opposites[pair[1]] = UInt32(pair[0])
        }
        var vertexToHalfEdge = [UInt32](repeating: .max, count: Int(source.max().map { $0 + 1 } ?? 0))
        for halfEdge in indices.indices {
            let vertex = Int(source[Int(indices[halfEdge])])
            if vertexToHalfEdge[vertex] == .max {
                vertexToHalfEdge[vertex] = UInt32(halfEdge)
            }
        }
        return (opposites, vertexToHalfEdge)
    }
}

public extension Mesh {
    /// Rebuilds a triangle mesh from indexed vertex arrays.
    ///
    /// Output vertices with the same ``Mesh/VertexArrays/sourceVertices`` entry become one mesh
    /// vertex. Each triangle becomes a face; each submesh keeps its label. With `opposites`
    /// (see ``Mesh/VertexArrays/cornerTable()``), twins are wired exactly; otherwise topology is
    /// rebuilt from shared vertices. Signed (`.float4`) tangents keep only xyz.
    init(vertexArrays arrays: VertexArrays, opposites: [UInt32]? = nil) {
        typealias VertexID = HalfEdgeTopology.VertexID
        typealias HalfEdgeID = HalfEdgeTopology.HalfEdgeID
        typealias FaceID = HalfEdgeTopology.FaceID

        func attribute(_ semantic: VertexDescriptor.Attribute.Semantic) -> MetalMesh.VertexAttributeData? {
            arrays.attributes.first { $0.semantic == semantic }
        }
        guard let positionData = attribute(.position) else {
            preconditionFailure("vertex arrays must contain a .position attribute")
        }
        let vertexPositions: [SIMD3<Float>] = positionData.values()

        // Dense mesh vertices, numbered by first appearance.
        var meshVertex: [Int: Int] = [:]
        var positions: [SIMD3<Float>] = []
        let vertexOf = arrays.sourceVertices.enumerated().map { output, source in
            if let existing = meshVertex[source.raw] {
                return existing
            }
            meshVertex[source.raw] = positions.count
            positions.append(vertexPositions[output])
            return positions.count - 1
        }

        var indices: [UInt32] = []
        var submeshes: [Submesh] = []
        for submesh in arrays.submeshes {
            precondition(submesh.primitiveType == .triangle, "Converting to Mesh requires triangle submeshes")
            let start = indices.count / 3
            indices += submesh.indices
            submeshes.append(Submesh(label: submesh.label, faces: (start..<indices.count / 3).map { FaceID(raw: $0) }))
        }
        let triangleCount = indices.count / 3

        let topology: HalfEdgeTopology
        if let opposites {
            precondition(opposites.count == indices.count, "opposites must have one entry per index")
            var vertices = positions.indices.map { HalfEdgeTopology.Vertex(id: VertexID(raw: $0), edge: nil) }
            let halfEdges = indices.indices.map { halfEdge in
                let base = (halfEdge / 3) * 3
                let origin = vertexOf[Int(indices[halfEdge])]
                if vertices[origin].edge == nil {
                    vertices[origin].edge = HalfEdgeID(raw: halfEdge)
                }
                return HalfEdgeTopology.HalfEdge(
                    id: HalfEdgeID(raw: halfEdge),
                    origin: VertexID(raw: origin),
                    twin: opposites[halfEdge] == .max ? nil : HalfEdgeID(raw: Int(opposites[halfEdge])),
                    next: HalfEdgeID(raw: base + (halfEdge + 1) % 3),
                    prev: HalfEdgeID(raw: base + (halfEdge + 2) % 3),
                    face: FaceID(raw: halfEdge / 3)
                )
            }
            var exact = HalfEdgeTopology()
            exact.vertices = vertices
            exact.halfEdges = halfEdges
            exact.faces = (0..<triangleCount).map { HalfEdgeTopology.Face(id: FaceID(raw: $0), edge: HalfEdgeID(raw: $0 * 3), holeEdges: []) }
            topology = exact
        } else {
            let faces = (0..<triangleCount).map { triangle in
                HalfEdgeTopology.FaceDefinition(outer: (0..<3).map { vertexOf[Int(indices[triangle * 3 + $0])] })
            }
            topology = HalfEdgeTopology(vertexCount: positions.count, faces: faces)
        }

        // Corner c of triangle t takes output vertex indices[t * 3 + c].
        var cornerSources = [Int](repeating: 0, count: topology.halfEdges.count)
        for triangle in 0..<triangleCount {
            for (corner, halfEdge) in topology.halfEdgeLoop(for: FaceID(raw: triangle)).enumerated() {
                cornerSources[halfEdge.raw] = Int(indices[triangle * 3 + corner])
            }
        }
        func corners<T: SIMD>(_ semantic: VertexDescriptor.Attribute.Semantic) -> [T]? where T.Scalar == Float {
            attribute(semantic).map { data in
                let values: [T] = data.values()
                return cornerSources.map { values[$0] }
            }
        }

        self.init(
            topology: topology,
            positions: positions,
            normals: corners(.normal),
            textureCoordinates: corners(.texcoord()),
            tangents: corners(.tangent),
            bitangents: corners(.bitangent),
            colors: corners(.color()),
            submeshes: submeshes
        )
    }
}

public extension MetalMesh {
    /// Reads the vertex and index buffers back into CPU arrays.
    ///
    /// Vertices with equal positions share a ``Mesh/VertexArrays/sourceVertices`` entry.
    /// Buffers must be CPU-visible.
    func vertexArrays() -> Mesh.VertexArrays {
        let attributes = vertexAttributeData()
        guard let positionData = attributes.first(where: { $0.semantic == .position }) else {
            preconditionFailure("MetalMesh has no .position attribute")
        }
        var firstVertex: [SIMD3<Float>: Int] = [:]
        let sourceVertices = (positionData.values() as [SIMD3<Float>]).map { position in
            if let existing = firstVertex[position] {
                return HalfEdgeTopology.VertexID(raw: existing)
            }
            firstVertex[position] = firstVertex.count
            return HalfEdgeTopology.VertexID(raw: firstVertex.count - 1)
        }
        let submeshIndices = submeshes.map { SubmeshIndices(label: $0.label, indices: $0.indices, primitiveType: $0.primitiveType) }
        return Mesh.VertexArrays(attributes: attributes, submeshes: submeshIndices, sourceVertices: sourceVertices)
    }
}
