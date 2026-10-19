import GeometryLite3D
import simd

public extension Mesh {
    /// The generalized winding number of the surface at `point`: the sum of the triangles' solid angles over 4π.
    ///
    /// About 1 inside and 0 outside an outward-wound closed mesh. Small holes and a few flipped faces only move the
    /// value a little, so it still classifies points of imperfect meshes. Pass a BVH built from this mesh to reuse
    /// its triangulation.
    func windingNumber(at point: SIMD3<Float>, bvh: TriangleBVH? = nil) -> Float {
        var sum: Double = 0
        if let bvh {
            for triangle in bvh.triangles {
                sum += Double(solidAngle(ofTriangle: triangle.a, triangle.b, triangle.c, from: point))
            }
        } else {
            for face in topology.faces {
                for corners in triangulatedCorners(of: face.id) {
                    let a = positions[topology.halfEdges[corners.0.raw].origin.raw]
                    let b = positions[topology.halfEdges[corners.1.raw].origin.raw]
                    let c = positions[topology.halfEdges[corners.2.raw].origin.raw]
                    sum += Double(solidAngle(ofTriangle: a, b, c, from: point))
                }
            }
        }
        return Float(sum / (4 * .pi))
    }

    /// Whether `point` is inside the mesh: its winding number is above one half.
    func contains(_ point: SIMD3<Float>, bvh: TriangleBVH? = nil) -> Bool {
        windingNumber(at: point, bvh: bvh) > 0.5
    }
}
