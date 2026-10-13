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

        public init(attributes: [MetalMesh.VertexAttributeData], submeshes: [MetalMesh.SubmeshIndices], sourceVertices: [HalfEdgeTopology.VertexID]) {
            self.attributes = attributes
            self.submeshes = submeshes
            self.sourceVertices = sourceVertices
        }
    }

    /// Per-corner glTF / MikkTSpace tangents: xyz is the tangent, w is the bitangent sign (±1).
    ///
    /// w is -1 where `cross(normal, tangent)` points away from the bitangent. Nil unless the mesh has normals,
    /// tangents and bitangents.
    var signedTangents: [SIMD4<Float>]? {
        guard let normals, let tangents, let bitangents else {
            return nil
        }
        return tangents.indices.map { index in
            Self.signedTangent(normal: normals[index], tangent: tangents[index], bitangent: bitangents[index])
        }
    }

    private static func signedTangent(normal: SIMD3<Float>, tangent: SIMD3<Float>, bitangent: SIMD3<Float>) -> SIMD4<Float> {
        SIMD4(tangent, simd_dot(simd_cross(normal, tangent), bitangent) < 0 ? -1 : 1)
    }

    /// Triangulates faces and turns corners into vertices. Corners with the same position and attributes share a vertex.
    ///
    /// With `signedTangents`, tangents are output as ``signedTangents`` and bitangents are left out.
    func vertexArrays(signedTangents: Bool = false) -> VertexArrays {
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
        if signedTangents, self.signedTangents != nil {
            attributes.append(.tangents(tangents.indices.map { index in
                Self.signedTangent(normal: normals[index], tangent: tangents[index], bitangent: bitangents[index])
            }))
        } else {
            if self.tangents != nil {
                attributes.append(.tangents(tangents))
            }
            if self.bitangents != nil {
                attributes.append(.bitangents(bitangents))
            }
        }
        if self.colors != nil {
            attributes.append(.colors(colors))
        }
        return VertexArrays(attributes: attributes, submeshes: submeshIndices, sourceVertices: sourceVertices)
    }
}
