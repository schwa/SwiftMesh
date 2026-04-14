import simd
import SwiftEarcut

// MARK: - Triangulation

extension Mesh {

    /// Triangulate all faces, returning triangle indices as triples of VertexIDs.
    ///
    /// - Triangles (3 vertices) are passed through unchanged.
    /// - Larger faces are projected onto a 2D plane (derived from face normal)
    ///   and triangulated via earcut.
    public func triangulate() -> [(HalfEdgeTopology.VertexID, HalfEdgeTopology.VertexID, HalfEdgeTopology.VertexID)] {
        var triangles: [(HalfEdgeTopology.VertexID, HalfEdgeTopology.VertexID, HalfEdgeTopology.VertexID)] = []

        for face in topology.faces {
            let verts = topology.vertexLoop(for: face.id)
            switch verts.count {
            case ..<3:
                continue
            case 3:
                triangles.append((verts[0], verts[1], verts[2]))
            default:
                let faceTriangles = triangulateFace(vertexIDs: verts)
                triangles.append(contentsOf: faceTriangles)
            }
        }

        return triangles
    }

    /// Triangulate a single face given its vertex IDs.
    func triangulateFace(vertexIDs: [HalfEdgeTopology.VertexID]) -> [(HalfEdgeTopology.VertexID, HalfEdgeTopology.VertexID, HalfEdgeTopology.VertexID)] {
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
