import simd

// MARK: - Mesh Merging

public extension Mesh {
    /// Merge multiple meshes into a single mesh.
    ///
    /// Positions are concatenated, face indices are offset, and per-corner
    /// attributes are combined.
    ///
    /// Each input's submeshes are preserved, with their ``Submesh/faces``
    /// ranges offset to point at the corresponding faces in the merged
    /// result. To collapse a source mesh into a single labeled submesh,
    /// assign `mesh.submeshes` before calling `merged(_:)`.
    ///
    /// Per-corner attributes (normals, UVs, tangents, bitangents, colors) are
    /// included only if **all** input meshes provide them; otherwise they are
    /// dropped from the result.
    ///
    /// - Parameter meshes: The meshes to merge, in order.
    /// - Returns: A new mesh containing all input geometry.
    static func merged(_ meshes: [Mesh]) -> Mesh {
        guard let first = meshes.first else {
            return Mesh(positions: [], faces: [] as [[Int]])
        }
        guard meshes.count > 1 else {
            return first
        }

        var allPositions: [SIMD3<Float>] = []
        var allFaceDefs: [HalfEdgeTopology.FaceDefinition] = []
        var allSubmeshes: [Submesh] = []

        var cornerParts: [CornerAttributes] = []

        for mesh in meshes {
            let vertexOffset = allPositions.count
            let faceOffset = allFaceDefs.count
            allPositions.append(contentsOf: mesh.positions)

            for face in mesh.topology.faces {
                let verts = mesh.topology.vertexLoop(for: face.id)
                let remapped = verts.map { $0.raw + vertexOffset }
                let holes = mesh.topology.holeVertexLoops(for: face.id).map { loop in
                    loop.map { $0.raw + vertexOffset }
                }

                allFaceDefs.append(.init(outer: remapped, holes: holes))
            }
            let corners = mesh.topology.faces.flatMap { mesh.topology.rebuildCornerOrder(for: $0.id).map(\.raw) }
            cornerParts.append(CornerAttributes(of: mesh).gathered(corners))

            // Preserve source submeshes, offsetting face IDs
            for sub in mesh.submeshes {
                let shifted = sub.faces.map { HalfEdgeTopology.FaceID(raw: $0.raw + faceOffset) }
                allSubmeshes.append(Submesh(label: sub.label, faces: shifted))
            }
        }

        let topo = HalfEdgeTopology(vertexCount: allPositions.count, faces: allFaceDefs)

        var result = Mesh(topology: topo, positions: allPositions, submeshes: allSubmeshes)
        CornerAttributes.concatenated(cornerParts).apply(to: &result)
        return result
    }

    /// Merge another mesh into this one.
    ///
    /// The other mesh's positions are appended; its submeshes are preserved
    /// (with face IDs offset). Self's existing submeshes are preserved with
    /// their face IDs unchanged. To make `other` contribute a single labeled
    /// submesh, assign `other.submeshes` before calling `merging(_:)`.
    ///
    /// Per-corner attributes are preserved when present on both meshes;
    /// attributes missing on either side are dropped from the result.
    ///
    /// - Parameter other: Mesh to merge into this one.
    /// - Returns: A new merged mesh.
    func merging(_ other: Mesh) -> Mesh {
        Self.merged([self, other])
    }
}
