import simd

public extension Mesh {
    /// A mesh flattened to indexed per-vertex arrays, as ``MetalMesh`` stores it but in CPU memory.
    struct VertexArrays {
        /// Positions, then whichever of normals, texture coordinates, tangents, bitangents and colors the mesh has.
        public var attributes: [MetalMesh.VertexAttributeData]
        /// One per ``Mesh/submeshes`` entry, as triangle lists.
        public var submeshes: [MetalMesh.SubmeshIndices]
        /// For each output vertex, the mesh vertex its position comes from.
        public var sourceVertices: [HalfEdgeTopology.VertexID]

        public var vertexCount: Int { sourceVertices.count }
    }

    /// Triangulates faces and turns corners into vertices. Corners with the same position and attributes share a vertex.
    func vertexArrays() -> VertexArrays {
        struct CornerKey: Hashable {
            var position: SIMD3<Float>
            var normal: SIMD3<Float>
            var textureCoordinate: SIMD2<Float>
            var tangent: SIMD3<Float>
            var bitangent: SIMD3<Float>
            var color: SIMD4<Float>
        }

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var textureCoordinates: [SIMD2<Float>] = []
        var tangents: [SIMD3<Float>] = []
        var bitangents: [SIMD3<Float>] = []
        var colors: [SIMD4<Float>] = []
        var sourceVertices: [HalfEdgeTopology.VertexID] = []
        var vertexIndices: [CornerKey: UInt32] = [:]

        let submeshIndices = submeshes.map { submesh in
            var indices: [UInt32] = []
            for face in submesh.faces {
                for triangle in triangulatedCorners(of: face) {
                    for corner in [triangle.0, triangle.1, triangle.2] {
                        let vertex = topology.halfEdges[corner.raw].origin
                        let key = CornerKey(
                            position: self.positions[vertex.raw],
                            normal: self.normals?[corner.raw] ?? .zero,
                            textureCoordinate: self.textureCoordinates?[corner.raw] ?? .zero,
                            tangent: self.tangents?[corner.raw] ?? .zero,
                            bitangent: self.bitangents?[corner.raw] ?? .zero,
                            color: self.colors?[corner.raw] ?? .zero
                        )
                        if let index = vertexIndices[key] {
                            indices.append(index)
                            continue
                        }
                        let index = UInt32(positions.count)
                        vertexIndices[key] = index
                        positions.append(key.position)
                        normals.append(key.normal)
                        textureCoordinates.append(key.textureCoordinate)
                        tangents.append(key.tangent)
                        bitangents.append(key.bitangent)
                        colors.append(key.color)
                        sourceVertices.append(vertex)
                        indices.append(index)
                    }
                }
            }
            return MetalMesh.SubmeshIndices(label: submesh.label, indices: indices)
        }

        var attributes: [MetalMesh.VertexAttributeData] = [.positions(positions)]
        if self.normals != nil {
            attributes.append(.normals(normals))
        }
        if self.textureCoordinates != nil {
            attributes.append(.textureCoordinates(textureCoordinates))
        }
        if self.tangents != nil {
            attributes.append(.tangents(tangents))
        }
        if self.bitangents != nil {
            attributes.append(.bitangents(bitangents))
        }
        if self.colors != nil {
            attributes.append(.colors(colors))
        }
        return VertexArrays(attributes: attributes, submeshes: submeshIndices, sourceVertices: sourceVertices)
    }
}
