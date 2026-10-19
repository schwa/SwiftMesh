import GeometryLite3D
import simd

// Fast generalized winding number (Barill et al. 2018, "Fast Winding Numbers for Soups and Clouds"). Each binary
// BVH node stores a Taylor expansion of the solid angle of its triangles about the node's center. Far from the node
// the expansion replaces the per-triangle sum.

extension TriangleBVH {
    struct WindingNode: Sendable {
        /// Area-weighted centroid of the node's triangles.
        var center: SIMD3<Float>
        /// Squared distance from `center` to the farthest corner of the node's box.
        var radiusSquared: Float
        /// Sum of area-weighted normals: the first-order (dipole) term.
        var normalSum: SIMD3<Float>
        /// Sum of area * (centroid - center) ⊗ normal: the second-order term.
        var moment: simd_float3x3
        /// Leaf: first triangle. Internal: right child (the left child is the next node).
        var offset: Int32
        /// Triangles in a leaf; 0 for an internal node.
        var triangleCount: Int32
    }

    /// Builds the expansion for every binary node. `nodes` come from the builder and index `triangles` (BVH order).
    static func windingNodes(_ nodes: [Node], triangles: [Triangle]) -> [WindingNode] {
        // Per node: area, area-weighted centroid sum, area-weighted normal sum, and sum of area * centroid ⊗ normal.
        // The moment about any center c is then that sum minus c ⊗ normalSum.
        var area = [Float](repeating: 0, count: nodes.count)
        var centroidSum = [SIMD3<Float>](repeating: .zero, count: nodes.count)
        var normalSum = [SIMD3<Float>](repeating: .zero, count: nodes.count)
        var outerSum = [simd_float3x3](repeating: simd_float3x3(), count: nodes.count)
        // Children always have larger indices than their parent.
        for index in nodes.indices.reversed() {
            let node = nodes[index]
            if node.isLeaf {
                for triangle in triangles[node.offset..<(node.offset + node.triangleCount)] {
                    let areaNormal = simd_cross(triangle.b - triangle.a, triangle.c - triangle.a) * 0.5
                    let triangleArea = simd_length(areaNormal)
                    let centroid = (triangle.a + triangle.b + triangle.c) / 3
                    area[index] += triangleArea
                    centroidSum[index] += centroid * triangleArea
                    normalSum[index] += areaNormal
                    outerSum[index] += simd_float3x3(columns: (centroid * areaNormal.x, centroid * areaNormal.y, centroid * areaNormal.z))
                }
            } else {
                for child in [index + 1, node.offset] {
                    area[index] += area[child]
                    centroidSum[index] += centroidSum[child]
                    normalSum[index] += normalSum[child]
                    outerSum[index] += outerSum[child]
                }
            }
        }
        return nodes.indices.map { index in
            let node = nodes[index]
            let center = area[index] > 0 ? centroidSum[index] / area[index] : (node.min + node.max) * 0.5
            let normals = normalSum[index]
            let moment = outerSum[index] - simd_float3x3(columns: (center * normals.x, center * normals.y, center * normals.z))
            var radiusSquared: Float = 0
            for corner in 0..<8 {
                let point = SIMD3<Float>(corner & 1 == 0 ? node.min.x : node.max.x, corner & 2 == 0 ? node.min.y : node.max.y, corner & 4 == 0 ? node.min.z : node.max.z)
                radiusSquared = max(radiusSquared, simd_distance_squared(point, center))
            }
            return WindingNode(center: center, radiusSquared: radiusSquared, normalSum: normals, moment: moment,
                               offset: Int32(node.offset), triangleCount: Int32(node.triangleCount))
        }
    }

    /// The generalized winding number at `point`. Nodes farther than `accuracy` times their radius use the
    /// second-order expansion; larger values are slower and more accurate.
    ///
    /// The default of 2 is meant for inside/outside tests: errors up to about 0.06 near 0 or 1, far from the 0.5
    /// threshold. An accuracy of 16 keeps errors below about 1e-3 at roughly 50 times the cost.
    public func windingNumber(at point: SIMD3<Float>, accuracy: Float = 2) -> Float {
        guard !windingNodes.isEmpty else {
            return 0
        }
        let accuracySquared = accuracy * accuracy
        var sum: Double = 0
        windingNodes.withUnsafeBufferPointer { nodes in
            triangles.withUnsafeBufferPointer { triangles in
                withUnsafeTemporaryAllocation(of: Int32.self, capacity: Self.maximumDepth + 2) { stack in
                    stack[0] = 0
                    var stackCount = 1
                    while stackCount > 0 {
                        stackCount -= 1
                        let nodeIndex = stack[stackCount]
                        let node = nodes[Int(nodeIndex)]
                        let r = node.center - point
                        let distanceSquared = simd_length_squared(r)
                        if distanceSquared > accuracySquared * node.radiusSquared {
                            let distance = distanceSquared.squareRoot()
                            let inverseCube = 1 / (distanceSquared * distance)
                            let moment = node.moment
                            let trace = moment.columns.0.x + moment.columns.1.y + moment.columns.2.z
                            let firstOrder = simd_dot(node.normalSum, r)
                            let secondOrder = trace - 3 * simd_dot(r, moment * r) / distanceSquared
                            sum += Double((firstOrder + secondOrder) * inverseCube)
                        } else if node.triangleCount > 0 {
                            let first = Int(node.offset)
                            for triangle in triangles[first..<(first + Int(node.triangleCount))] {
                                sum += Double(solidAngle(ofTriangle: triangle.a, triangle.b, triangle.c, from: point))
                            }
                        } else {
                            stack[stackCount] = node.offset
                            stack[stackCount + 1] = nodeIndex + 1
                            stackCount += 2
                        }
                    }
                }
            }
        }
        return Float(sum / (4 * .pi))
    }
}
