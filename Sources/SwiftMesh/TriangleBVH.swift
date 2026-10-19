import GeometryLite3D
import simd

/// A bounding volume hierarchy over a mesh's triangles, for closest-point and ray queries.
///
/// Built once from the triangulated faces; it does not track later edits to the mesh.
public struct TriangleBVH: Sendable {
    public struct Triangle: Sendable, Equatable {
        public var a: SIMD3<Float>
        public var b: SIMD3<Float>
        public var c: SIMD3<Float>
        /// The mesh face this triangle came from.
        public var face: HalfEdgeTopology.FaceID

        public init(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, face: HalfEdgeTopology.FaceID) {
            self.a = a
            self.b = b
            self.c = c
            self.face = face
        }
    }

    public struct ClosestPoint: Sendable, Equatable {
        public var point: SIMD3<Float>
        public var distance: Float
        /// Index into `triangles`.
        public var triangle: Int
        /// Weights for the triangle's vertices (a, b, c).
        public var barycentrics: SIMD3<Float>
    }

    public struct RayHit: Sendable, Equatable {
        public var distance: Float
        /// Index into `triangles`.
        public var triangle: Int
        /// Weights for the triangle's vertices (a, b, c).
        public var barycentrics: SIMD3<Float>
    }

    struct Node: Sendable {
        var min: SIMD3<Float>
        var max: SIMD3<Float>
        /// Leaf: first triangle. Internal: index of the right child (the left child is the next node).
        var offset: Int
        /// Number of triangles in a leaf; 0 for an internal node.
        var triangleCount: Int

        var isLeaf: Bool { triangleCount != 0 }
    }

    /// Triangles in BVH order. Query results index into this array.
    public private(set) var triangles: [Triangle]
    private(set) var nodes: [Node] = []

    static let maximumLeafSize = 4

    public init(mesh: Mesh) {
        var triangles: [Triangle] = []
        for face in mesh.topology.faces {
            for corners in mesh.triangulatedCorners(of: face.id) {
                let halfEdges = mesh.topology.halfEdges
                triangles.append(Triangle(
                    mesh.positions[halfEdges[corners.0.raw].origin.raw],
                    mesh.positions[halfEdges[corners.1.raw].origin.raw],
                    mesh.positions[halfEdges[corners.2.raw].origin.raw],
                    face: face.id
                ))
            }
        }
        self.init(triangles: triangles)
    }

    public init(triangles: [Triangle]) {
        self.triangles = triangles
        guard !triangles.isEmpty else {
            return
        }
        let centroids = triangles.map { ($0.a + $0.b + $0.c) / 3 }
        var order = Array(triangles.indices)
        nodes.reserveCapacity(2 * triangles.count / Self.maximumLeafSize + 1)
        build(range: 0..<order.count, order: &order, centroids: centroids)
        self.triangles = order.map { triangles[$0] }
    }

    private mutating func build(range: Range<Int>, order: inout [Int], centroids: [SIMD3<Float>]) {
        var boxMin = SIMD3<Float>(repeating: .infinity)
        var boxMax = SIMD3<Float>(repeating: -.infinity)
        var centroidMin = SIMD3<Float>(repeating: .infinity)
        var centroidMax = SIMD3<Float>(repeating: -.infinity)
        for index in order[range] {
            let triangle = triangles[index]
            boxMin = simd_min(boxMin, simd_min(triangle.a, simd_min(triangle.b, triangle.c)))
            boxMax = simd_max(boxMax, simd_max(triangle.a, simd_max(triangle.b, triangle.c)))
            centroidMin = simd_min(centroidMin, centroids[index])
            centroidMax = simd_max(centroidMax, centroids[index])
        }
        let nodeIndex = nodes.count
        nodes.append(Node(min: boxMin, max: boxMax, offset: range.lowerBound, triangleCount: range.count))

        let extent = centroidMax - centroidMin
        guard range.count > Self.maximumLeafSize, simd_reduce_max(extent) > 0 else {
            return
        }
        let axis = extent.x >= extent.y ? (extent.x >= extent.z ? 0 : 2) : (extent.y >= extent.z ? 1 : 2)
        order[range].sort { centroids[$0][axis] < centroids[$1][axis] }
        let middle = (range.lowerBound + range.upperBound) / 2

        nodes[nodeIndex].triangleCount = 0
        build(range: range.lowerBound..<middle, order: &order, centroids: centroids)
        nodes[nodeIndex].offset = nodes.count
        build(range: middle..<range.upperBound, order: &order, centroids: centroids)
    }

    /// The closest point on any triangle to `point`, or nil when there are no triangles.
    public func closestPoint(to point: SIMD3<Float>) -> ClosestPoint? {
        guard !nodes.isEmpty else {
            return nil
        }
        var best: ClosestPoint?
        var bestDistanceSquared = Float.infinity
        var stack = [0]
        while let nodeIndex = stack.popLast() {
            let node = nodes[nodeIndex]
            guard Self.distanceSquared(from: point, toBoxMin: node.min, max: node.max) < bestDistanceSquared else {
                continue
            }
            if node.isLeaf {
                for index in node.offset..<(node.offset + node.triangleCount) {
                    let triangle = triangles[index]
                    let candidate = GeometryLite3D.closestPoint(onTriangle: triangle.a, triangle.b, triangle.c, to: point)
                    let distanceSquared = simd_distance_squared(candidate.point, point)
                    if distanceSquared < bestDistanceSquared {
                        bestDistanceSquared = distanceSquared
                        best = ClosestPoint(point: candidate.point, distance: 0, triangle: index, barycentrics: candidate.barycentrics)
                    }
                }
            } else {
                let left = nodeIndex + 1
                let right = node.offset
                let leftDistance = Self.distanceSquared(from: point, toBoxMin: nodes[left].min, max: nodes[left].max)
                let rightDistance = Self.distanceSquared(from: point, toBoxMin: nodes[right].min, max: nodes[right].max)
                // Push the farther child first so the nearer one is searched first.
                if leftDistance < rightDistance {
                    stack.append(right)
                    stack.append(left)
                } else {
                    stack.append(left)
                    stack.append(right)
                }
            }
        }
        best?.distance = bestDistanceSquared.squareRoot()
        return best
    }

    /// The nearest triangle hit along `ray`, or nil when the ray misses.
    public func intersect(ray: Ray3D, cullBackFaces: Bool = false) -> RayHit? {
        guard !nodes.isEmpty else {
            return nil
        }
        let inverseDirection = 1 / ray.direction
        var best: RayHit?
        var bestDistance = Float.infinity
        var stack = [0]
        while let nodeIndex = stack.popLast() {
            let node = nodes[nodeIndex]
            guard let entry = Self.slabEntry(ray: ray, inverseDirection: inverseDirection, boxMin: node.min, max: node.max), entry <= bestDistance else {
                continue
            }
            if node.isLeaf {
                for index in node.offset..<(node.offset + node.triangleCount) {
                    let triangle = triangles[index]
                    if let hit = ray.intersect(triangle: triangle.a, triangle.b, triangle.c, cullBackFaces: cullBackFaces), hit.distance < bestDistance {
                        bestDistance = hit.distance
                        best = RayHit(distance: hit.distance, triangle: index, barycentrics: hit.barycentrics)
                    }
                }
            } else {
                stack.append(node.offset)
                stack.append(nodeIndex + 1)
            }
        }
        return best
    }

    static func distanceSquared(from point: SIMD3<Float>, toBoxMin boxMin: SIMD3<Float>, max boxMax: SIMD3<Float>) -> Float {
        let offset = simd_max(simd_max(boxMin - point, point - boxMax), .zero)
        return simd_length_squared(offset)
    }

    /// Distance along the ray where it enters the box (0 when the origin is inside), or nil on a miss.
    static func slabEntry(ray: Ray3D, inverseDirection: SIMD3<Float>, boxMin: SIMD3<Float>, max boxMax: SIMD3<Float>) -> Float? {
        let t0 = (boxMin - ray.origin) * inverseDirection
        let t1 = (boxMax - ray.origin) * inverseDirection
        // 0 * infinity gives NaN when an axis-parallel ray starts on a slab plane; that axis then does not limit the ray.
        let unbounded = (t0 .!= t0) .| (t1 .!= t1)
        let near = simd_reduce_max(simd_min(t0, t1).replacing(with: -.infinity, where: unbounded))
        let far = simd_reduce_min(simd_max(t0, t1).replacing(with: .infinity, where: unbounded))
        guard far >= Swift.max(near, 0) else {
            return nil
        }
        return Swift.max(near, 0)
    }
}
