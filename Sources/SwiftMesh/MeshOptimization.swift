import simd

public extension Mesh {
    /// Merge adjacent coplanar faces into larger polygons.
    ///
    /// Faces whose normals are within `angleTolerance` radians and whose
    /// planes are within `distanceTolerance` are considered coplanar.
    /// Shared edges between coplanar faces are removed, merging them
    /// into single polygons.
    ///
    /// This is useful as a post-processing step after CSG operations,
    /// which tend to over-triangulate flat surfaces.
    func mergingCoplanarFaces(angleTolerance: Float = 1e-4, distanceTolerance: Float = 1e-4) -> Mesh {
        var topo = topology
        let positions = self.positions

        // Build face planes
        struct FacePlane {
            var normal: SIMD3<Float>
            var distance: Float // dot(normal, pointOnFace)
        }

        var facePlanes: [HalfEdgeTopology.FaceID: FacePlane] = [:]
        for face in topo.faces {
            let n = faceNormal(face.id)
            let verts = topo.vertexLoop(for: face.id)
            guard !verts.isEmpty else { continue }
            let d = simd_dot(n, positions[verts[0].raw])
            facePlanes[face.id] = FacePlane(normal: n, distance: d)
        }

        func areCoplanar(_ a: HalfEdgeTopology.FaceID, _ b: HalfEdgeTopology.FaceID) -> Bool {
            guard let pa = facePlanes[a], let pb = facePlanes[b] else { return false }
            let dot = simd_dot(pa.normal, pb.normal)
            guard dot >= cos(angleTolerance) else { return false }
            return abs(pa.distance - pb.distance) < distanceTolerance
        }

        // Find interior edges between coplanar faces and delete them.
        // Collect candidates first, then delete (modifying topology during iteration is unsafe).
        var edgesToDelete: [HalfEdgeTopology.HalfEdgeID] = []

        for he in topo.halfEdges {
            // Only process each undirected edge once (use the one with the lower ID)
            guard let twinID = he.twin, he.id.raw < twinID.raw else { continue }
            guard let faceA = he.face, let faceB = topo.halfEdges[twinID.raw].face else { continue }
            guard faceA != faceB else { continue }
            // Check both faces are still valid (have edges)
            guard topo.faces[faceA.raw].edge != nil, topo.faces[faceB.raw].edge != nil else { continue }

            if areCoplanar(faceA, faceB) {
                edgesToDelete.append(he.id)
            }
        }

        // Delete edges one at a time. After each deletion the merged face inherits
        // the ID of one of the two original faces, so subsequent deletions that
        // reference the other face ID may now find it on the merged face.
        for heID in edgesToDelete {
            // Verify the edge is still valid (hasn't been removed by a prior deletion)
            let he = topo.halfEdges[heID.raw]
            guard he.next != nil, he.face != nil else { continue }
            topo.deleteEdge(heID)
        }

        // Rebuild mesh from modified topology, keeping only faces that still have edges.
        // Remove collinear vertices from face boundaries — these are leftover from
        // deleted interior edges and produce degenerate/crossed edges.
        let liveFaces = topo.faces.filter { $0.edge != nil }
        var newFaces: [[Int]] = []
        for face in liveFaces {
            let verts = topo.vertexLoop(for: face.id)
            guard verts.count >= 3 else { continue }
            let cleaned = removeCollinearVertices(verts.map(\.raw), positions: positions)
            guard cleaned.count >= 3 else { continue }
            newFaces.append(cleaned)
        }

        return Mesh(positions: positions, faces: newFaces)
    }
}

/// Remove vertices that lie on the straight line between their neighbors.
private func removeCollinearVertices(_ indices: [Int], positions: [SIMD3<Float>], tolerance: Float = 1e-4) -> [Int] {
    guard indices.count >= 3 else { return indices }
    var result: [Int] = []
    let n = indices.count
    for i in 0..<n {
        let prev = positions[indices[(i + n - 1) % n]]
        let curr = positions[indices[i]]
        let next = positions[indices[(i + 1) % n]]

        let edge1 = curr - prev
        let edge2 = next - curr
        let cross = simd_cross(edge1, edge2)
        // If cross product magnitude is near zero relative to edge lengths,
        // the vertex is collinear and can be removed.
        let crossLen = simd_length(cross)
        let edgeLen = simd_length(edge1) * simd_length(edge2)
        if edgeLen > 0 && crossLen / edgeLen < tolerance {
            continue // skip collinear vertex
        }
        result.append(indices[i])
    }
    return result
}
