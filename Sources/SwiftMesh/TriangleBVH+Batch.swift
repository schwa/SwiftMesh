import simd

extension TriangleBVH {
    /// Exact distances from four points to the surface, in one shared traversal.
    ///
    /// Each node is loaded once and box-tested for all four points; a child is visited when it could still hold the
    /// nearest triangle of any point. Nearby points visit nearly the same nodes, so this costs much less than four
    /// separate `closestPoint(to:)` calls. Infinity when there are no triangles.
    func distances(toPointsX xs: SIMD4<Float>, y ys: SIMD4<Float>, z zs: SIMD4<Float>) -> SIMD4<Float> {
        guard !wideNodes.isEmpty else {
            return SIMD4(repeating: .infinity)
        }
        var best = SIMD4<Float>(repeating: .infinity)
        let points = (
            (SIMD4(repeating: xs.x), SIMD4(repeating: ys.x), SIMD4(repeating: zs.x)),
            (SIMD4(repeating: xs.y), SIMD4(repeating: ys.y), SIMD4(repeating: zs.y)),
            (SIMD4(repeating: xs.z), SIMD4(repeating: ys.z), SIMD4(repeating: zs.z)),
            (SIMD4(repeating: xs.w), SIMD4(repeating: ys.w), SIMD4(repeating: zs.w))
        )
        @inline(__always)
        func boxDistances(_ node: WideNode, _ point: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)) -> SIMD4<Float> {
            let dx = simd_max(simd_max(node.minX - point.0, point.0 - node.maxX), .zero)
            let dy = simd_max(simd_max(node.minY - point.1, point.1 - node.maxY), .zero)
            let dz = simd_max(simd_max(node.minZ - point.2, point.2 - node.maxZ), .zero)
            return dx * dx + dy * dy + dz * dz
        }
        wideNodes.withUnsafeBufferPointer { nodes in
            blocks.withUnsafeBufferPointer { blocks in
                blockDots.withUnsafeBufferPointer { blockDots in
                    withUnsafeTemporaryAllocation(of: StackEntry.self, capacity: stackCapacity) { stack in
                        stack[0] = StackEntry(child: 0, triangleCount: 0, distance: 0)
                        var stackCount = 1
                        while stackCount > 0 {
                            stackCount -= 1
                            let entry = stack[stackCount]
                            // `distance` is the smallest box distance over the points; skip when no point can improve.
                            guard entry.distance < simd_reduce_max(best) else {
                                continue
                            }
                            if entry.triangleCount > 0 {
                                let firstBlock = Int(entry.child)
                                for blockIndex in firstBlock..<(firstBlock + (Int(entry.triangleCount) + 3) / 4) {
                                    let block = blocks[blockIndex]
                                    let dots = blockDots[blockIndex]
                                    best.x = Swift.min(best.x, simd_reduce_min(Self.distancesSquared(block, dots, px: points.0.0, py: points.0.1, pz: points.0.2).0))
                                    best.y = Swift.min(best.y, simd_reduce_min(Self.distancesSquared(block, dots, px: points.1.0, py: points.1.1, pz: points.1.2).0))
                                    best.z = Swift.min(best.z, simd_reduce_min(Self.distancesSquared(block, dots, px: points.2.0, py: points.2.1, pz: points.2.2).0))
                                    best.w = Swift.min(best.w, simd_reduce_min(Self.distancesSquared(block, dots, px: points.3.0, py: points.3.1, pz: points.3.2).0))
                                }
                                continue
                            }
                            let node = nodes[Int(entry.child)]
                            let d0 = boxDistances(node, points.0)
                            let d1 = boxDistances(node, points.1)
                            let d2 = boxDistances(node, points.2)
                            let d3 = boxDistances(node, points.3)
                            // A child is needed when some point's box distance beats that point's best.
                            let needed = (d0 .< best.x) .| (d1 .< best.y) .| (d2 .< best.z) .| (d3 .< best.w)
                            let keys = simd_min(simd_min(d0, d1), simd_min(d2, d3))
                            let distances = SIMD4<Float>(repeating: .infinity).replacing(with: keys, where: needed)
                            Self.pushSorted(distances: distances, node: node, limit: .infinity, stack: stack, stackCount: &stackCount)
                        }
                    }
                }
            }
        }
        return best.squareRoot()
    }
}
