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

        // Determine which per-corner attributes all meshes share
        let hasNormals = meshes.allSatisfy { $0.normals != nil }
        let hasTexCoords = meshes.allSatisfy { $0.textureCoordinates != nil }
        let hasTangents = meshes.allSatisfy { $0.tangents != nil }
        let hasBitangents = meshes.allSatisfy { $0.bitangents != nil }
        let hasColors = meshes.allSatisfy { $0.colors != nil }

        // Accumulate per-corner attributes in face order, then map to new half-edges
        var allNormals: [SIMD3<Float>] = []
        var allTexCoords: [SIMD2<Float>] = []
        var allTangents: [SIMD3<Float>] = []
        var allBitangents: [SIMD3<Float>] = []
        var allColors: [SIMD4<Float>] = []

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

                // Collect per-corner attributes in face-loop order
                let heLoop = mesh.topology.halfEdgeLoop(for: face.id)
                for he in heLoop {
                    if hasNormals { allNormals.append(mesh.normals![he.raw]) }
                    if hasTexCoords { allTexCoords.append(mesh.textureCoordinates![he.raw]) }
                    if hasTangents { allTangents.append(mesh.tangents![he.raw]) }
                    if hasBitangents { allBitangents.append(mesh.bitangents![he.raw]) }
                    if hasColors { allColors.append(mesh.colors![he.raw]) }
                }
            }

            // Preserve source submeshes, offsetting face IDs
            for sub in mesh.submeshes {
                let shifted = sub.faces.map { HalfEdgeTopology.FaceID(raw: $0.raw + faceOffset) }
                allSubmeshes.append(Submesh(label: sub.label, faces: shifted))
            }
        }

        let topo = HalfEdgeTopology(vertexCount: allPositions.count, faces: allFaceDefs)

        // Map accumulated per-corner attributes into the new topology's half-edge order.
        // Face order and loop order are preserved by HalfEdgeTopology.init, so we walk
        // them in parallel.
        var newNormals: [SIMD3<Float>]?
        var newTexCoords: [SIMD2<Float>]?
        var newTangents: [SIMD3<Float>]?
        var newBitangents: [SIMD3<Float>]?
        var newColors: [SIMD4<Float>]?

        if hasNormals { newNormals = [SIMD3<Float>](repeating: .zero, count: topo.halfEdges.count) }
        if hasTexCoords { newTexCoords = [SIMD2<Float>](repeating: .zero, count: topo.halfEdges.count) }
        if hasTangents { newTangents = [SIMD3<Float>](repeating: .zero, count: topo.halfEdges.count) }
        if hasBitangents { newBitangents = [SIMD3<Float>](repeating: .zero, count: topo.halfEdges.count) }
        if hasColors { newColors = [SIMD4<Float>](repeating: .zero, count: topo.halfEdges.count) }

        var cornerIdx = 0
        for faceIdx in 0..<topo.faces.count {
            let faceID = HalfEdgeTopology.FaceID(raw: faceIdx)
            let heLoop = topo.halfEdgeLoop(for: faceID)
            for he in heLoop {
                if hasNormals { newNormals![he.raw] = allNormals[cornerIdx] }
                if hasTexCoords { newTexCoords![he.raw] = allTexCoords[cornerIdx] }
                if hasTangents { newTangents![he.raw] = allTangents[cornerIdx] }
                if hasBitangents { newBitangents![he.raw] = allBitangents[cornerIdx] }
                if hasColors { newColors![he.raw] = allColors[cornerIdx] }
                cornerIdx += 1
            }
        }

        return Mesh(
            topology: topo,
            positions: allPositions,
            normals: newNormals,
            textureCoordinates: newTexCoords,
            tangents: newTangents,
            bitangents: newBitangents,
            colors: newColors,
            submeshes: allSubmeshes
        )
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
        Mesh.merged([self, other])
    }
}
