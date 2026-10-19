import GeometryLite3D
import simd

extension TriangleBVH {
    /// Four child boxes stored per axis, so one node tests all four with SIMD.
    ///
    /// A child is a node (`counts` is 0, `children` is its node index), a leaf (`counts` > 0, `children` is its
    /// first triangle) or empty (`counts` is -1, with an inverted box).
    struct WideNode: Sendable {
        var minX = SIMD4<Float>(repeating: .infinity)
        var minY = SIMD4<Float>(repeating: .infinity)
        var minZ = SIMD4<Float>(repeating: .infinity)
        var maxX = SIMD4<Float>(repeating: -.infinity)
        var maxY = SIMD4<Float>(repeating: -.infinity)
        var maxZ = SIMD4<Float>(repeating: -.infinity)
        var children = SIMD4<Int32>(repeating: 0)
        var counts = SIMD4<Int32>(repeating: -1)
    }

    /// Up to four triangles of one leaf, stored per component: vertex a and edges b - a and c - a.
    struct TriangleBlock: Sendable {
        var ax = SIMD4<Float>.zero, ay = SIMD4<Float>.zero, az = SIMD4<Float>.zero
        var abx = SIMD4<Float>.zero, aby = SIMD4<Float>.zero, abz = SIMD4<Float>.zero
        var acx = SIMD4<Float>.zero, acy = SIMD4<Float>.zero, acz = SIMD4<Float>.zero
        /// Index in `triangles` of lane 0; the lanes are consecutive triangles.
        var first: Int32 = 0
        /// Lanes in use, padded lanes are ignored.
        var valid = SIMDMask<SIMD4<Int32>>(repeating: false)
    }

    /// Edge dot products for each triangle block, read only by closest-point queries.
    struct BlockDots: Sendable {
        var abab: SIMD4<Float>
        var abac: SIMD4<Float>
        var acac: SIMD4<Float>

        init(_ block: TriangleBlock) {
            abab = block.abx * block.abx + block.aby * block.aby + block.abz * block.abz
            abac = block.abx * block.acx + block.aby * block.acy + block.abz * block.acz
            acac = block.acx * block.acx + block.acy * block.acy + block.acz * block.acz
        }
    }

    struct StackEntry {
        var child: Int32
        var triangleCount: Int32
        var distance: Float
    }

    /// Entries a traversal stack needs for a wide tree of the given depth: each level pushes at most three entries
    /// beyond the one it pops.
    static func stackCapacity(depth: Int) -> Int {
        3 * depth + 4
    }

    /// Collapses a binary tree (root at 0, left child next, right child at `offset`) into a 4-wide tree, with leaf
    /// triangles packed into blocks. Leaves point at their first block and hold their triangle count.
    func collapse(_ nodes: [Node]) -> ([WideNode], [TriangleBlock], depth: Int) {
        var depth = 0
        var blocks: [TriangleBlock] = []
        func makeBlocks(first: Int, count: Int) -> Int {
            let start = blocks.count
            for blockFirst in stride(from: first, to: first + count, by: 4) {
                var block = TriangleBlock()
                block.first = Int32(blockFirst)
                for lane in 0..<Swift.min(4, first + count - blockFirst) {
                    let index = blockFirst + lane
                    block.ax[lane] = vertexA[index].x
                    block.ay[lane] = vertexA[index].y
                    block.az[lane] = vertexA[index].z
                    block.abx[lane] = edgeAB[index].x
                    block.aby[lane] = edgeAB[index].y
                    block.abz[lane] = edgeAB[index].z
                    block.acx[lane] = edgeAC[index].x
                    block.acy[lane] = edgeAC[index].y
                    block.acz[lane] = edgeAC[index].z
                    block.valid[lane] = true
                }
                blocks.append(block)
            }
            return start
        }
        var wide: [WideNode] = []
        wide.reserveCapacity(nodes.count / 2 + 1)
        func area(_ node: Node) -> Float {
            let size = simd_max(node.max - node.min, .zero)
            return size.x * size.y + size.y * size.z + size.z * size.x
        }
        // Fills wide node `index` from binary node `root`. The internal children of a node are allocated next to each
        // other before any is filled, so siblings sit together in memory.
        func emit(_ root: Int, into index: Int, level: Int) {
            depth = Swift.max(depth, level)
            // Open the largest internal child until there are four.
            var slots = nodes[root].isLeaf ? [root] : [root + 1, nodes[root].offset]
            while slots.count < 4 {
                guard let open = slots.indices.filter({ !nodes[slots[$0]].isLeaf }).max(by: { area(nodes[slots[$0]]) < area(nodes[slots[$1]]) }) else {
                    break
                }
                let node = slots.remove(at: open)
                slots.append(node + 1)
                slots.append(nodes[node].offset)
            }
            for (lane, slot) in slots.enumerated() {
                let node = nodes[slot]
                wide[index].minX[lane] = node.min.x
                wide[index].minY[lane] = node.min.y
                wide[index].minZ[lane] = node.min.z
                wide[index].maxX[lane] = node.max.x
                wide[index].maxY[lane] = node.max.y
                wide[index].maxZ[lane] = node.max.z
                if node.isLeaf {
                    wide[index].children[lane] = Int32(makeBlocks(first: node.offset, count: node.triangleCount))
                    wide[index].counts[lane] = Int32(node.triangleCount)
                } else {
                    wide[index].counts[lane] = 0
                }
            }
            var childIndices: [(slot: Int, index: Int)] = []
            for (lane, slot) in slots.enumerated() where !nodes[slot].isLeaf {
                wide[index].children[lane] = Int32(wide.count)
                childIndices.append((slot, wide.count))
                wide.append(WideNode())
            }
            for child in childIndices {
                emit(child.slot, into: child.index, level: level + 1)
            }
        }
        wide.append(WideNode())
        emit(0, into: 0, level: 1)
        return (wide, blocks, depth)
    }

    /// Squared distance from `p` to each triangle of the block (Ericson 5.1.5, branch-free); infinity in padded lanes.
    @inline(__always)
    static func distancesSquared(_ block: TriangleBlock, _ dots: BlockDots, px: SIMD4<Float>, py: SIMD4<Float>, pz: SIMD4<Float>) -> (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) {
        let abab = dots.abab, abac = dots.abac, acac = dots.acac
        let apx = px - block.ax, apy = py - block.ay, apz = pz - block.az
        let d1 = block.abx * apx + block.aby * apy + block.abz * apz
        let d2 = block.acx * apx + block.acy * apy + block.acz * apz
        // bp = ap - ab, cp = ap - ac
        let d3 = d1 - abab
        let d4 = d2 - abac
        let d5 = d1 - abac
        let d6 = d2 - acac
        let vc = d1 * d4 - d3 * d2
        let vb = d5 * d2 - d1 * d6
        let va = d3 * d6 - d5 * d4
        // Face region first, then regions in reverse priority so the first matching region wins.
        let denominator = va + vb + vc
        var v = vb / denominator
        var w = vc / denominator
        let zero = SIMD4<Float>.zero
        let one = SIMD4<Float>(repeating: 1)
        let regionBC = (va .<= 0) .& (d4 - d3 .>= 0) .& (d5 - d6 .>= 0)
        let wBC = (d4 - d3) / ((d4 - d3) + (d5 - d6))
        v.replace(with: one - wBC, where: regionBC)
        w.replace(with: wBC, where: regionBC)
        let regionAC = (vb .<= 0) .& (d2 .>= 0) .& (d6 .<= 0)
        v.replace(with: zero, where: regionAC)
        w.replace(with: d2 / (d2 - d6), where: regionAC)
        let regionC = (d6 .>= 0) .& (d5 .<= d6)
        v.replace(with: zero, where: regionC)
        w.replace(with: one, where: regionC)
        let regionAB = (vc .<= 0) .& (d1 .>= 0) .& (d3 .<= 0)
        v.replace(with: d1 / (d1 - d3), where: regionAB)
        w.replace(with: zero, where: regionAB)
        let regionB = (d3 .>= 0) .& (d4 .<= d3)
        v.replace(with: one, where: regionB)
        w.replace(with: zero, where: regionB)
        let regionA = (d1 .<= 0) .& (d2 .<= 0)
        v.replace(with: zero, where: regionA)
        w.replace(with: zero, where: regionA)
        let rx = apx - v * block.abx - w * block.acx
        let ry = apy - v * block.aby - w * block.acy
        let rz = apz - v * block.abz - w * block.acz
        let distances = rx * rx + ry * ry + rz * rz
        return (SIMD4<Float>(repeating: .infinity).replacing(with: distances, where: block.valid .& (distances .== distances)), v, w)
    }

    /// The closest point on any triangle to `point`, or nil when there are no triangles.
    public func closestPoint(to point: SIMD3<Float>) -> ClosestPoint? {
        guard !wideNodes.isEmpty else {
            return nil
        }
        var bestTriangle = -1
        var bestPoint = SIMD3<Float>.zero
        var bestBarycentrics = SIMD3<Float>.zero
        var bestDistanceSquared = Float.infinity
        let px = SIMD4<Float>(repeating: point.x)
        let py = SIMD4<Float>(repeating: point.y)
        let pz = SIMD4<Float>(repeating: point.z)
        wideNodes.withUnsafeBufferPointer { nodes in
          blocks.withUnsafeBufferPointer { blocks in
          blockDots.withUnsafeBufferPointer { blockDots in
            vertexA.withUnsafeBufferPointer { vertexA in
                edgeAB.withUnsafeBufferPointer { edgeAB in
                    edgeAC.withUnsafeBufferPointer { edgeAC in
                        withUnsafeTemporaryAllocation(of: StackEntry.self, capacity: stackCapacity) { stack in
                            stack[0] = StackEntry(child: 0, triangleCount: 0, distance: 0)
                            var stackCount = 1
                            while stackCount > 0 {
                                stackCount -= 1
                                let entry = stack[stackCount]
                                guard entry.distance < bestDistanceSquared else {
                                    continue
                                }
                                if entry.triangleCount > 0 {
                                    let firstBlock = Int(entry.child)
                                    for blockIndex in firstBlock..<(firstBlock + (Int(entry.triangleCount) + 3) / 4) {
                                        let block = blocks[blockIndex]
                                        let (distances, v, w) = Self.distancesSquared(block, blockDots[blockIndex], px: px, py: py, pz: pz)
                                        let nearest = simd_reduce_min(distances)
                                        guard nearest < bestDistanceSquared else {
                                            continue
                                        }
                                        let lane = distances[0] == nearest ? 0 : distances[1] == nearest ? 1 : distances[2] == nearest ? 2 : 3
                                        let index = Int(block.first) + lane
                                        bestDistanceSquared = nearest
                                        bestPoint = vertexA[index] + v[lane] * edgeAB[index] + w[lane] * edgeAC[index]
                                        bestBarycentrics = SIMD3(1 - v[lane] - w[lane], v[lane], w[lane])
                                        bestTriangle = index
                                    }
                                    continue
                                }
                                let node = nodes[Int(entry.child)]
                                let dx = simd_max(simd_max(node.minX - px, px - node.maxX), .zero)
                                let dy = simd_max(simd_max(node.minY - py, py - node.maxY), .zero)
                                let dz = simd_max(simd_max(node.minZ - pz, pz - node.maxZ), .zero)
                                let distances = dx * dx + dy * dy + dz * dz
                                Self.pushSorted(distances: distances, node: node, limit: bestDistanceSquared, stack: stack, stackCount: &stackCount)
                            }
                        }
                    }
                }
            }
          }
          }
        }
        guard bestTriangle >= 0 else {
            return nil
        }
        return ClosestPoint(point: bestPoint, distance: bestDistanceSquared.squareRoot(), triangle: bestTriangle, barycentrics: bestBarycentrics)
    }

    /// The nearest triangle hit along `ray`, or nil when the ray misses.
    public func intersect(ray: Ray3D, cullBackFaces: Bool = false) -> RayHit? {
        guard !wideNodes.isEmpty else {
            return nil
        }
        // A zero direction component makes 0 * infinity possible in the slab test, which needs the slower NaN-safe version.
        if any(ray.direction .== 0) {
            return intersect(ray: ray, cullBackFaces: cullBackFaces, slabTest: NaNSafeSlabTest.self)
        }
        return intersect(ray: ray, cullBackFaces: cullBackFaces, slabTest: PlainSlabTest.self)
    }

    @inline(__always)
    private func intersect<Test: SlabTest>(ray: Ray3D, cullBackFaces: Bool, slabTest _: Test.Type) -> RayHit? {
        let origin = ray.origin
        let direction = ray.direction
        let inverse = 1 / direction
        let ox = SIMD4<Float>(repeating: origin.x)
        let oy = SIMD4<Float>(repeating: origin.y)
        let oz = SIMD4<Float>(repeating: origin.z)
        let ix = SIMD4<Float>(repeating: inverse.x)
        let iy = SIMD4<Float>(repeating: inverse.y)
        let iz = SIMD4<Float>(repeating: inverse.z)
        var bestTriangle = -1
        var bestBarycentrics = SIMD3<Float>.zero
        var bestDistance = Float.infinity
        wideNodes.withUnsafeBufferPointer { nodes in
          blocks.withUnsafeBufferPointer { blocks in
            vertexA.withUnsafeBufferPointer { _ in
                edgeAB.withUnsafeBufferPointer { _ in
                    edgeAC.withUnsafeBufferPointer { _ in
                        withUnsafeTemporaryAllocation(of: StackEntry.self, capacity: stackCapacity) { stack in
                            stack[0] = StackEntry(child: 0, triangleCount: 0, distance: 0)
                            var stackCount = 1
                            while stackCount > 0 {
                                stackCount -= 1
                                let entry = stack[stackCount]
                                guard entry.distance < bestDistance else {
                                    continue
                                }
                                if entry.triangleCount > 0 {
                                    let firstBlock = Int(entry.child)
                                    for blockIndex in firstBlock..<(firstBlock + (Int(entry.triangleCount) + 3) / 4) {
                                        let block = blocks[blockIndex]
                                        let (distances, u, v) = Self.hits(block, ox: ox, oy: oy, oz: oz, direction: direction, cullBackFaces: cullBackFaces)
                                        let nearest = simd_reduce_min(distances)
                                        guard nearest < bestDistance else {
                                            continue
                                        }
                                        let lane = distances[0] == nearest ? 0 : distances[1] == nearest ? 1 : distances[2] == nearest ? 2 : 3
                                        bestDistance = nearest
                                        bestBarycentrics = SIMD3(1 - u[lane] - v[lane], u[lane], v[lane])
                                        bestTriangle = Int(block.first) + lane
                                    }
                                    continue
                                }
                                let node = nodes[Int(entry.child)]
                                let entries = Test.entries(node: node, ox: ox, oy: oy, oz: oz, ix: ix, iy: iy, iz: iz)
                                Self.pushSorted(distances: entries, node: node, limit: bestDistance, stack: stack, stackCount: &stackCount)
                            }
                        }
                    }
                }
            }
          }
        }
        guard bestTriangle >= 0 else {
            return nil
        }
        return RayHit(distance: bestDistance, triangle: bestTriangle, barycentrics: bestBarycentrics)
    }

    /// Möller–Trumbore hit distance for each triangle of the block; infinity on a miss or a padded lane.
    /// Same tests as `intersectTriangle`; also returns barycentric u, v.
    @inline(__always)
    static func hits(_ block: TriangleBlock, ox: SIMD4<Float>, oy: SIMD4<Float>, oz: SIMD4<Float>, direction: SIMD3<Float>, cullBackFaces: Bool) -> (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) {
        let dx = SIMD4<Float>(repeating: direction.x), dy = SIMD4<Float>(repeating: direction.y), dz = SIMD4<Float>(repeating: direction.z)
        // p = direction x ac
        let pX = dy * block.acz - dz * block.acy
        let pY = dz * block.acx - dx * block.acz
        let pZ = dx * block.acy - dy * block.acx
        let determinant = block.abx * pX + block.aby * pY + block.abz * pZ
        let inverse = 1 / determinant
        let sx = ox - block.ax, sy = oy - block.ay, sz = oz - block.az
        let u = (sx * pX + sy * pY + sz * pZ) * inverse
        // q = s x ab
        let qX = sy * block.abz - sz * block.aby
        let qY = sz * block.abx - sx * block.abz
        let qZ = sx * block.aby - sy * block.abx
        let v = (dx * qX + dy * qY + dz * qZ) * inverse
        let t = (block.acx * qX + block.acy * qY + block.acz * qZ) * inverse
        let epsilon: Float = 1e-12
        var hit = block.valid .& (u .>= 0) .& (u .<= 1) .& (v .>= 0) .& (u + v .<= 1) .& (t .>= 0)
        hit .&= cullBackFaces ? (determinant .>= epsilon) : (abs(determinant) .>= epsilon)
        return (SIMD4<Float>(repeating: .infinity).replacing(with: t, where: hit), u, v)
    }

    /// Ray-box slab tests for the four children of a node.
    protocol SlabTest {
        /// Near and far distances of the ray inside one axis slab.
        static func axis(_ lower: SIMD4<Float>, _ upper: SIMD4<Float>, _ origin: SIMD4<Float>, _ inverse: SIMD4<Float>) -> (SIMD4<Float>, SIMD4<Float>)
    }

    /// For rays with no zero direction component, so no product is NaN.
    enum PlainSlabTest: SlabTest {
        @inline(__always)
        static func axis(_ lower: SIMD4<Float>, _ upper: SIMD4<Float>, _ origin: SIMD4<Float>, _ inverse: SIMD4<Float>) -> (SIMD4<Float>, SIMD4<Float>) {
            let t0 = (lower - origin) * inverse
            let t1 = (upper - origin) * inverse
            return (simd_min(t0, t1), simd_max(t0, t1))
        }
    }

    /// 0 * infinity gives NaN when an axis-parallel ray starts on a slab plane; that axis then does not limit the ray.
    enum NaNSafeSlabTest: SlabTest {
        @inline(__always)
        static func axis(_ lower: SIMD4<Float>, _ upper: SIMD4<Float>, _ origin: SIMD4<Float>, _ inverse: SIMD4<Float>) -> (SIMD4<Float>, SIMD4<Float>) {
            let t0 = (lower - origin) * inverse
            let t1 = (upper - origin) * inverse
            let unbounded = (t0 .!= t0) .| (t1 .!= t1)
            return (simd_min(t0, t1).replacing(with: -.infinity, where: unbounded), simd_max(t0, t1).replacing(with: .infinity, where: unbounded))
        }
    }

    /// Pushes children closer than `limit`, farthest first, so the nearest is popped next.
    @inline(__always)
    static func pushSorted(distances: SIMD4<Float>, node: WideNode, limit: Float, stack: UnsafeMutableBufferPointer<StackEntry>, stackCount: inout Int) {
        let start = stackCount
        for lane in 0..<4 where distances[lane] < limit {
            let entry = StackEntry(child: node.children[lane], triangleCount: node.counts[lane], distance: distances[lane])
            // Insertion sort, descending by distance.
            var position = stackCount
            while position > start, stack[position - 1].distance < entry.distance {
                stack[position] = stack[position - 1]
                position -= 1
            }
            stack[position] = entry
            stackCount += 1
        }
    }
}

extension TriangleBVH.SlabTest {
    /// Entry distance for each child box (0 when the origin is inside), or infinity on a miss or an empty child.
    @inline(__always)
    static func entries(node: TriangleBVH.WideNode, ox: SIMD4<Float>, oy: SIMD4<Float>, oz: SIMD4<Float>, ix: SIMD4<Float>, iy: SIMD4<Float>, iz: SIMD4<Float>) -> SIMD4<Float> {
        let (nearX, farX) = axis(node.minX, node.maxX, ox, ix)
        let (nearY, farY) = axis(node.minY, node.maxY, oy, iy)
        let (nearZ, farZ) = axis(node.minZ, node.maxZ, oz, iz)
        let near = simd_max(simd_max(nearX, nearY), simd_max(nearZ, .zero))
        let far = simd_min(farX, simd_min(farY, farZ))
        let hit = (far .>= near) .& (node.counts .>= 0)
        return SIMD4<Float>(repeating: .infinity).replacing(with: near, where: hit)
    }
}
