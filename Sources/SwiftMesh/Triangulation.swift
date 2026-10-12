import simd

// MARK: - Triangulation

extension Mesh {
    /// Triangulate all faces (including their holes), returning triangles as triples of VertexIDs.
    public func triangulate() -> [(HalfEdgeTopology.VertexID, HalfEdgeTopology.VertexID, HalfEdgeTopology.VertexID)] {
        topology.faces.flatMap { face in
            triangulatedCorners(of: face.id).map { corners in
                (topology.halfEdges[corners.0.raw].origin, topology.halfEdges[corners.1.raw].origin, topology.halfEdges[corners.2.raw].origin)
            }
        }
    }

    /// Triangles covering a face, holes excluded, as triples of its corners (half-edges).
    ///
    /// Corners carry the vertex and the per-corner attributes, so callers can copy attributes
    /// exactly. Triangles pass through; larger faces and faces with holes are projected on the
    /// axis plane closest to the face normal and triangulated with the robust ε-aware
    /// triangulator, which always returns a manifold triangulation of the face.
    public func triangulatedCorners(of face: HalfEdgeTopology.FaceID) -> [(HalfEdgeTopology.HalfEdgeID, HalfEdgeTopology.HalfEdgeID, HalfEdgeTopology.HalfEdgeID)] {
        let outer = topology.halfEdgeLoop(for: face)
        guard outer.count >= 3 else {
            return []
        }
        let holes = topology.faces[face.raw].holeEdges.map { topology.collectHalfEdgeLoop(startEdge: $0) }.filter { $0.count >= 3 }
        if outer.count == 3, holes.isEmpty {
            return [(outer[0], outer[1], outer[2])]
        }
        let project = axisAlignedProjection(SIMD3<Double>(faceNormal(face)))
        let polygons = ([outer] + holes).map { loop in
            loop.map { PolyVert(pos: project(SIMD3<Double>(positions[topology.halfEdges[$0.raw].origin.raw])), idx: $0.raw) }
        }
        let points = polygons.flatMap { $0.map(\.pos) }
        let scale = points.reduce(0) { max($0, max(abs($1.x), abs($1.y))) }
        let epsilon = max(BooleanMesh.relativePrecision, Double(Float.ulpOfOne)) * scale
        return SwiftMesh.triangulate(polygons, epsilon: epsilon).map { triangle in
            (HalfEdgeTopology.HalfEdgeID(raw: triangle.x), HalfEdgeTopology.HalfEdgeID(raw: triangle.y), HalfEdgeTopology.HalfEdgeID(raw: triangle.z))
        }
    }

    /// Return a new mesh where every face is a triangle.
    ///
    /// Faces that are already triangles are preserved. Larger polygons and faces with holes
    /// are split with ``triangulatedCorners(of:)``. Positions are shared; per-corner
    /// attributes (normals, UVs, colors, tangents, bitangents) are carried over
    /// from the original corners.
    public func triangulated() -> Mesh {
        let newPositions = positions
        var newFaces: [[Int]] = []

        // Old corner index for each new corner, in new half-edge order
        var corners: [Int] = []

        for face in topology.faces where face.edge != nil {
            for triangle in triangulatedCorners(of: face.id) {
                let triangleCorners = [triangle.0, triangle.1, triangle.2]
                newFaces.append(triangleCorners.map { topology.halfEdges[$0.raw].origin.raw })
                corners += triangleCorners.map(\.raw)
            }
        }

        // Build new topology
        let faceDefs = newFaces.map { HalfEdgeTopology.FaceDefinition(outer: $0) }
        let topo = HalfEdgeTopology(vertexCount: newPositions.count, faces: faceDefs)

        var result = Mesh(topology: topo, positions: newPositions)
        CornerAttributes(of: self).gathered(corners).apply(to: &result)
        return result
    }
}
