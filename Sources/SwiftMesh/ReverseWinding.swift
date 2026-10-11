public extension Mesh {
    /// The same mesh with every face loop reversed (flips which side is the front).
    ///
    /// Per-corner attributes stay with their vertex; normals are not negated.
    func reversingWinding() -> Mesh {
        var definitions: [HalfEdgeTopology.FaceDefinition] = []
        var corners: [Int] = []
        var faceMap: [HalfEdgeTopology.FaceID: HalfEdgeTopology.FaceID] = [:]

        // Reversed loop keeps its first corner: [h0, h(n-1), ..., h1].
        func reversed(_ loop: [HalfEdgeTopology.HalfEdgeID]) -> [HalfEdgeTopology.HalfEdgeID] {
            loop.isEmpty ? [] : [loop[0]] + loop.dropFirst().reversed()
        }

        for face in topology.faces where face.edge != nil {
            let outer = topology.halfEdgeLoop(for: face.id)
            guard outer.count >= 3 else {
                continue
            }
            let holes = face.holeEdges.map { topology.collectHalfEdgeLoop(startEdge: $0) }.filter { $0.count >= 3 }
            let loops = ([outer] + holes).map(reversed)
            faceMap[face.id] = .init(raw: definitions.count)
            definitions.append(.init(
                outer: loops[0].map { topology.halfEdges[$0.raw].origin.raw },
                holes: loops.dropFirst().map { $0.map { topology.halfEdges[$0.raw].origin.raw } }
            ))
            corners += loops.flatMap { $0.map(\.raw) }
        }

        var result = Mesh(
            topology: HalfEdgeTopology(vertexCount: positions.count, faces: definitions),
            positions: positions,
            submeshes: submeshes.map { Submesh(label: $0.label, faces: $0.faces.compactMap { faceMap[$0] }) }
        )
        CornerAttributes(of: self).gathered(corners).apply(to: &result)
        return result
    }
}
