import Foundation
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

    /// 32 bytes. The `w` lanes hold bit patterns: `lower.w` is the first triangle (leaf) or the right child
    /// (internal; the left child is the next node), `upper.w` the leaf's triangle count (0 for internal nodes).
    struct Node: Sendable {
        var lower: SIMD4<Float>
        var upper: SIMD4<Float>

        init(min: SIMD3<Float>, max: SIMD3<Float>, offset: Int, triangleCount: Int) {
            lower = SIMD4(min, Float(bitPattern: UInt32(offset)))
            upper = SIMD4(max, Float(bitPattern: UInt32(triangleCount)))
        }

        var min: SIMD3<Float> { SIMD3(lower.x, lower.y, lower.z) }
        var max: SIMD3<Float> { SIMD3(upper.x, upper.y, upper.z) }
        var offset: Int {
            get { Int(lower.w.bitPattern) }
            set { lower.w = Float(bitPattern: UInt32(newValue)) }
        }
        var triangleCount: Int {
            get { Int(upper.w.bitPattern) }
            set { upper.w = Float(bitPattern: UInt32(newValue)) }
        }
        var isLeaf: Bool { upper.w.bitPattern != 0 }
    }

    /// Triangles in BVH order. Query results index into this array.
    public private(set) var triangles: [Triangle]
    private(set) var wideNodes: [WideNode] = []
    /// Per triangle in BVH order: vertex a and the edges b - a and c - a.
    private(set) var vertexA: [SIMD3<Float>] = []
    private(set) var edgeAB: [SIMD3<Float>] = []
    private(set) var edgeAC: [SIMD3<Float>] = []
    /// Leaf triangles in groups of four for SIMD tests.
    private(set) var blocks: [TriangleBlock] = []
    private(set) var blockDots: [BlockDots] = []
    /// Binary nodes with winding-number expansions, for `windingNumber(at:accuracy:)`.
    private(set) var windingNodes: [WindingNode] = []
    /// Traversal stack size for this tree; small enough to stay off the heap for typical trees.
    private(set) var stackCapacity = 0

    static let maximumLeafSize = 4
    /// Traversal stacks are fixed-size, so the tree depth is capped.
    static let maximumDepth = 60

    public init(mesh: Mesh) {
        // Faces are independent, so chunks are gathered in parallel and joined in face order.
        let faceCount = mesh.topology.faces.count
        let chunkSize = 2_048
        let chunkCount = (faceCount + chunkSize - 1) / chunkSize
        var chunks = [[Triangle]](repeating: [], count: chunkCount)
        chunks.withUnsafeMutableBufferPointer { buffer in
            // Each task writes only its own chunk.
            nonisolated(unsafe) let chunks = buffer
            DispatchQueue.concurrentPerform(iterations: chunkCount) { chunk in
                let start = chunk * chunkSize
                chunks[chunk] = Self.triangles(of: mesh, faces: start..<Swift.min(start + chunkSize, faceCount))
            }
        }
        self.init(triangles: Array(chunks.joined()))
    }

    private static func triangles(of mesh: Mesh, faces: Range<Int>) -> [Triangle] {
        var triangles: [Triangle] = []
        triangles.reserveCapacity(faces.count)
        let halfEdges = mesh.topology.halfEdges
        let positions = mesh.positions
        for face in mesh.topology.faces[faces] {
            // Fast path for a plain triangle: walk the loop directly instead of collecting it into an array.
            if face.holeEdges.isEmpty, let first = face.edge, let second = halfEdges[first.raw].next,
               let third = halfEdges[second.raw].next, halfEdges[third.raw].next == first {
                triangles.append(Triangle(
                    positions[halfEdges[first.raw].origin.raw],
                    positions[halfEdges[second.raw].origin.raw],
                    positions[halfEdges[third.raw].origin.raw],
                    face: face.id
                ))
                continue
            }
            for corners in mesh.triangulatedCorners(of: face.id) {
                triangles.append(Triangle(
                    mesh.positions[halfEdges[corners.0.raw].origin.raw],
                    mesh.positions[halfEdges[corners.1.raw].origin.raw],
                    mesh.positions[halfEdges[corners.2.raw].origin.raw],
                    face: face.id
                ))
            }
        }
        return triangles
    }

    public init(triangles: [Triangle]) {
        self.triangles = triangles
        guard !triangles.isEmpty else {
            return
        }
        var builder = Builder(triangles: triangles)
        builder.build(range: 0..<triangles.count, depth: 0)
        self.triangles = builder.order.map { triangles[$0] }
        vertexA = self.triangles.map(\.a)
        edgeAB = self.triangles.map { $0.b - $0.a }
        edgeAC = self.triangles.map { $0.c - $0.a }
        let depth: Int
        (wideNodes, blocks, depth) = collapse(builder.nodes)
        stackCapacity = Self.stackCapacity(depth: depth)
        blockDots = blocks.map(BlockDots.init)
        windingNodes = Self.windingNodes(builder.nodes, triangles: self.triangles)
    }

    /// Top-down build with a binned surface area heuristic (SAH).
    struct Builder {
        static let binCount = 32
        /// Cost of visiting a node, relative to testing one triangle.
        static let traversalCost: Float = 2

        var boxMin: [SIMD3<Float>]
        var boxMax: [SIMD3<Float>]
        var centroids: [SIMD3<Float>]
        var order: [Int]
        var nodes: [Node] = []
        var binLower = [SIMD3<Float>](repeating: .zero, count: 3 * binCount)
        var binUpper = [SIMD3<Float>](repeating: .zero, count: 3 * binCount)
        var binCounts = [Int](repeating: 0, count: 3 * binCount)
        var rightCost = [Float](repeating: 0, count: binCount)

        init(triangles: [Triangle]) {
            boxMin = triangles.map { simd_min($0.a, simd_min($0.b, $0.c)) }
            boxMax = triangles.map { simd_max($0.a, simd_max($0.b, $0.c)) }
            centroids = zip(boxMin, boxMax).map { ($0 + $1) * 0.5 }
            order = Array(triangles.indices)
            nodes.reserveCapacity(2 * triangles.count / 2 + 1)
        }

        /// Cost of testing `count` triangles: they are tested four at a time, so a partly filled block costs a full one.
        static func testCost(_ count: Int) -> Float {
            Float((count + 3) / 4 * 4)
        }

        static func halfArea(_ lower: SIMD3<Float>, _ upper: SIMD3<Float>) -> Float {
            let size = simd_max(upper - lower, .zero)
            return size.x * size.y + size.y * size.z + size.z * size.x
        }

        mutating func build(range: Range<Int>, depth: Int) {
            var lower = SIMD3<Float>(repeating: .infinity)
            var upper = SIMD3<Float>(repeating: -.infinity)
            var centroidLower = SIMD3<Float>(repeating: .infinity)
            var centroidUpper = SIMD3<Float>(repeating: -.infinity)
            for position in range {
                let index = order[position]
                lower = simd_min(lower, boxMin[index])
                upper = simd_max(upper, boxMax[index])
                centroidLower = simd_min(centroidLower, centroids[index])
                centroidUpper = simd_max(centroidUpper, centroids[index])
            }
            let nodeIndex = nodes.count
            nodes.append(Node(min: lower, max: upper, offset: range.lowerBound, triangleCount: range.count))

            let extent = centroidUpper - centroidLower
            guard range.count > 1, depth < TriangleBVH.maximumDepth, simd_reduce_max(extent) > 0 else {
                return
            }

            // Bin centroids on every axis and find the cheapest split.
            let binCount = Self.binCount
            // Zero scale on flat axes puts every centroid in bin 0 there (those axes are not split).
            let scale = (SIMD3<Float>(repeating: Float(binCount)) / extent).replacing(with: 0, where: extent .<= 0)
            var bestCost = Float.infinity
            var bestAxis = 0
            var bestSplit = 0
            // Reusable scratch bins for all three axes (slot = axis * binCount + bin), filled in one pass.
            for slot in 0..<(3 * binCount) {
                binLower[slot] = SIMD3(repeating: .infinity)
                binUpper[slot] = SIMD3(repeating: -.infinity)
                binCounts[slot] = 0
            }
            for position in range {
                let index = order[position]
                let lowerBox = boxMin[index]
                let upperBox = boxMax[index]
                let centroid = centroids[index]
                for axis in 0..<3 {
                    let slot = axis * binCount + Swift.min(binCount - 1, Int((centroid[axis] - centroidLower[axis]) * scale[axis]))
                    binCounts[slot] += 1
                    binLower[slot] = simd_min(binLower[slot], lowerBox)
                    binUpper[slot] = simd_max(binUpper[slot], upperBox)
                }
            }
            for axis in 0..<3 where extent[axis] > 0 {
                let base = axis * binCount
                // Sweep from the right, then from the left.
                var sweepLower = SIMD3<Float>(repeating: .infinity)
                var sweepUpper = SIMD3<Float>(repeating: -.infinity)
                var sweepCount = 0
                for bin in stride(from: binCount - 1, to: 0, by: -1) {
                    sweepLower = simd_min(sweepLower, binLower[base + bin])
                    sweepUpper = simd_max(sweepUpper, binUpper[base + bin])
                    sweepCount += binCounts[base + bin]
                    rightCost[bin] = Self.halfArea(sweepLower, sweepUpper) * Self.testCost(sweepCount)
                }
                sweepLower = SIMD3(repeating: .infinity)
                sweepUpper = SIMD3(repeating: -.infinity)
                sweepCount = 0
                for split in 1..<binCount {
                    sweepLower = simd_min(sweepLower, binLower[base + split - 1])
                    sweepUpper = simd_max(sweepUpper, binUpper[base + split - 1])
                    sweepCount += binCounts[base + split - 1]
                    guard sweepCount > 0, sweepCount < range.count else {
                        continue
                    }
                    let cost = Self.halfArea(sweepLower, sweepUpper) * Self.testCost(sweepCount) + rightCost[split]
                    if cost < bestCost {
                        bestCost = cost
                        bestAxis = axis
                        bestSplit = split
                    }
                }
            }

            let leafCost = Self.testCost(range.count)
            let splitCost = Self.traversalCost + bestCost / Self.halfArea(lower, upper)
            if range.count <= TriangleBVH.maximumLeafSize, leafCost <= splitCost {
                return
            }

            var middle: Int
            if bestCost.isFinite {
                // Partition by bin.
                var left = range.lowerBound
                var right = range.upperBound - 1
                while left <= right {
                    let index = order[left]
                    let bin = Swift.min(binCount - 1, Int((centroids[index][bestAxis] - centroidLower[bestAxis]) * scale[bestAxis]))
                    if bin < bestSplit {
                        left += 1
                    } else {
                        order.swapAt(left, right)
                        right -= 1
                    }
                }
                middle = left
            } else {
                middle = range.lowerBound
            }
            if middle == range.lowerBound || middle == range.upperBound {
                // All centroids fell in one bin: split at the median of the longest axis.
                let axis = extent.x >= extent.y ? (extent.x >= extent.z ? 0 : 2) : (extent.y >= extent.z ? 1 : 2)
                let centroids = centroids
                order[range].sort { centroids[$0][axis] < centroids[$1][axis] }
                middle = (range.lowerBound + range.upperBound) / 2
            }

            nodes[nodeIndex].triangleCount = 0
            let leftRange = range.lowerBound..<middle
            let rightRange = middle..<range.upperBound
            if depth < Self.parallelDepth, range.count >= Self.parallelMinimumCount {
                buildInParallel(nodeIndex: nodeIndex, leftRange: leftRange, rightRange: rightRange, depth: depth + 1)
                return
            }
            build(range: leftRange, depth: depth + 1)
            nodes[nodeIndex].offset = nodes.count
            build(range: rightRange, depth: depth + 1)
        }

        /// Top levels split into up to 2^parallelDepth subtrees that build at the same time.
        static let parallelDepth = 3
        static let parallelMinimumCount = 4_096

        /// Builds the two children on separate copies of the builder, then appends their nodes in pre-order.
        /// Each copy only reorders its own range of `order`, so the ranges are copied back without overlap.
        private mutating func buildInParallel(nodeIndex: Int, leftRange: Range<Int>, rightRange: Range<Int>, depth: Int) {
            var children = [self, self]
            for index in children.indices {
                children[index].nodes = []
            }
            let ranges = [leftRange, rightRange]
            children.withUnsafeMutableBufferPointer { buffer in
                // Each task writes only its own element.
                nonisolated(unsafe) let builders = buffer
                DispatchQueue.concurrentPerform(iterations: 2) { child in
                    builders[child].build(range: ranges[child], depth: depth)
                }
            }
            for (child, range) in zip(children, ranges) {
                if range == rightRange {
                    nodes[nodeIndex].offset = nodes.count
                }
                let base = nodes.count
                for var node in child.nodes {
                    if !node.isLeaf {
                        node.offset += base
                    }
                    nodes.append(node)
                }
                order.replaceSubrange(range, with: child.order[range])
            }
        }
    }

    /// Möller–Trumbore, matching `Ray3D.intersect(triangle:cullBackFaces:)`. Returns distance and barycentric u, v.
    @inline(__always)
    static func intersectTriangle(origin: SIMD3<Float>, direction: SIMD3<Float>, _ a: SIMD3<Float>, _ edge1: SIMD3<Float>, _ edge2: SIMD3<Float>, cullBackFaces: Bool) -> (Float, Float, Float)? {
        let epsilon: Float = 1e-12
        let p = simd_cross(direction, edge2)
        let determinant = simd_dot(edge1, p)
        if cullBackFaces {
            if determinant < epsilon {
                return nil
            }
        } else if abs(determinant) < epsilon {
            return nil
        }
        let inverseDeterminant = 1 / determinant
        let s = origin - a
        let u = simd_dot(s, p) * inverseDeterminant
        if u < 0 || u > 1 {
            return nil
        }
        let q = simd_cross(s, edge1)
        let v = simd_dot(direction, q) * inverseDeterminant
        if v < 0 || u + v > 1 {
            return nil
        }
        let distance = simd_dot(edge2, q) * inverseDeterminant
        if distance < 0 {
            return nil
        }
        return (distance, u, v)
    }

    /// Ericson, Real-Time Collision Detection 5.1.5, matching GeometryLite3D's `closestPoint(onTriangle:)`.
    @inline(__always)
    static func closestPointOnTriangle(_ a: SIMD3<Float>, _ ab: SIMD3<Float>, _ ac: SIMD3<Float>, to p: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
        let ap = p - a
        let d1 = simd_dot(ab, ap)
        let d2 = simd_dot(ac, ap)
        if d1 <= 0, d2 <= 0 {
            return (a, [1, 0, 0])
        }
        let bp = ap - ab
        let d3 = simd_dot(ab, bp)
        let d4 = simd_dot(ac, bp)
        if d3 >= 0, d4 <= d3 {
            return (a + ab, [0, 1, 0])
        }
        let vc = d1 * d4 - d3 * d2
        if vc <= 0, d1 >= 0, d3 <= 0 {
            let v = d1 / (d1 - d3)
            return (a + v * ab, [1 - v, v, 0])
        }
        let cp = ap - ac
        let d5 = simd_dot(ab, cp)
        let d6 = simd_dot(ac, cp)
        if d6 >= 0, d5 <= d6 {
            return (a + ac, [0, 0, 1])
        }
        let vb = d5 * d2 - d1 * d6
        if vb <= 0, d2 >= 0, d6 <= 0 {
            let w = d2 / (d2 - d6)
            return (a + w * ac, [1 - w, 0, w])
        }
        let va = d3 * d6 - d5 * d4
        if va <= 0, d4 - d3 >= 0, d5 - d6 >= 0 {
            let w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
            return (a + ab + w * (ac - ab), [0, 1 - w, w])
        }
        let denominator = va + vb + vc
        let v = vb / denominator
        let w = vc / denominator
        return (a + ab * v + ac * w, [1 - v - w, v, w])
    }
}
