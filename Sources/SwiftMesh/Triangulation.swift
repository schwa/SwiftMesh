import simd
import SwiftEarcut

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

    /// Triangulate a single face given its vertex IDs.
    ///
    /// Triangles are passed through unchanged. Larger faces are projected onto
    /// a 2D plane derived from the face normal and triangulated via earcut.
    public func triangulateFace(vertexIDs: [HalfEdgeTopology.VertexID]) -> [(HalfEdgeTopology.VertexID, HalfEdgeTopology.VertexID, HalfEdgeTopology.VertexID)] {
        let pts3D = vertexIDs.map { positions[$0.raw] }

        // Build local 2D frame from face normal
        let normal = computeNormal(pts3D)
        let (tangent, bitangent) = buildTangentFrame(normal: normal)

        // Project to 2D
        let origin = pts3D[0]
        let pts2D: [SIMD2<Float>] = pts3D.map { pt in
            let delta = pt - origin
            return SIMD2<Float>(simd_dot(delta, tangent), simd_dot(delta, bitangent))
        }

        // Run earcut
        let earcutIndices = earcut(polygon: [pts2D])

        // Map back to VertexIDs
        var result: [(HalfEdgeTopology.VertexID, HalfEdgeTopology.VertexID, HalfEdgeTopology.VertexID)] = []
        for triIdx in stride(from: 0, to: earcutIndices.count, by: 3) {
            let idx0 = Int(earcutIndices[triIdx])
            let idx1 = Int(earcutIndices[triIdx + 1])
            let idx2 = Int(earcutIndices[triIdx + 2])
            result.append((vertexIDs[idx0], vertexIDs[idx1], vertexIDs[idx2]))
        }

        return result
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

// MARK: - Internal helpers

/// Compute face normal via Newell's method.
private func computeNormal(_ points: [SIMD3<Float>]) -> SIMD3<Float> {
    var normal = SIMD3<Float>.zero
    let count = points.count
    for idx in 0..<count {
        let current = points[idx]
        let next = points[(idx + 1) % count]
        normal.x += (current.y - next.y) * (current.z + next.z)
        normal.y += (current.z - next.z) * (current.x + next.x)
        normal.z += (current.x - next.x) * (current.y + next.y)
    }
    let len = simd_length(normal)
    return len > 0 ? normal / len : SIMD3<Float>(0, 0, 1)
}

/// Build an orthonormal tangent frame from a normal vector.
private func buildTangentFrame(normal: SIMD3<Float>) -> (tangent: SIMD3<Float>, bitangent: SIMD3<Float>) {
    // Pick a reference vector not parallel to normal
    let reference: SIMD3<Float>
    if abs(normal.x) < 0.9 {
        reference = SIMD3<Float>(1, 0, 0)
    } else {
        reference = SIMD3<Float>(0, 1, 0)
    }
    let tangent = simd_normalize(simd_cross(normal, reference))
    let bitangent = simd_cross(normal, tangent)
    return (tangent, bitangent)
}
