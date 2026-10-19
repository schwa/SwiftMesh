import GeometryLite3D
import simd

public extension Mesh {
    struct ClosestPoint: Sendable, Equatable {
        public var point: SIMD3<Float>
        public var distance: Float
        public var face: HalfEdgeTopology.FaceID
        /// Unit normal of the triangle that holds `point`; zero for a degenerate triangle.
        public var normal: SIMD3<Float>
    }

    /// The closest point on the surface to `point`, or nil when the mesh has no triangles.
    ///
    /// Pass a BVH built from this mesh to avoid testing every triangle.
    func closestPoint(to point: SIMD3<Float>, bvh: TriangleBVH? = nil) -> ClosestPoint? {
        if let bvh {
            guard let hit = bvh.closestPoint(to: point) else {
                return nil
            }
            let triangle = bvh.triangles[hit.triangle]
            return ClosestPoint(point: hit.point, distance: hit.distance, face: triangle.face, normal: Self.triangleNormal(triangle.a, triangle.b, triangle.c))
        }
        var best: ClosestPoint?
        var bestDistanceSquared = Float.infinity
        for face in topology.faces {
            for corners in triangulatedCorners(of: face.id) {
                let a = positions[topology.halfEdges[corners.0.raw].origin.raw]
                let b = positions[topology.halfEdges[corners.1.raw].origin.raw]
                let c = positions[topology.halfEdges[corners.2.raw].origin.raw]
                let candidate = GeometryLite3D.closestPoint(onTriangle: a, b, c, to: point).point
                let distanceSquared = simd_distance_squared(candidate, point)
                if distanceSquared < bestDistanceSquared {
                    bestDistanceSquared = distanceSquared
                    best = ClosestPoint(point: candidate, distance: 0, face: face.id, normal: Self.triangleNormal(a, b, c))
                }
            }
        }
        best?.distance = bestDistanceSquared.squareRoot()
        return best
    }

    /// Distance from `point` to the surface, or nil when the mesh has no triangles.
    func distance(to point: SIMD3<Float>, bvh: TriangleBVH? = nil) -> Float? {
        closestPoint(to: point, bvh: bvh)?.distance
    }

    private static func triangleNormal(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> SIMD3<Float> {
        simd_cross(b - a, c - a).normalized(or: .zero)
    }
}
