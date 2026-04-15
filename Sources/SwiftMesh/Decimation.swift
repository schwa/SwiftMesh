import simd

// MARK: - Quadric Error Metrics decimation

/// A symmetric 4×4 matrix representing the quadric error at a vertex.
///
/// Stored as 10 unique values (upper triangle) for efficiency.
/// Represents the sum of squared distances to adjacent planes.
private struct Quadric: Sendable {
    // Upper triangle of symmetric 4×4:
    // [ a  b  c  d ]
    // [ b  e  f  g ]
    // [ c  f  h  i ]
    // [ d  g  i  j ]
    var a, b, c, d, e, f, g, h, i, j: Float

    static let zero = Self(a: 0, b: 0, c: 0, d: 0, e: 0, f: 0, g: 0, h: 0, i: 0, j: 0)

    /// Build a quadric from a plane equation (nx, ny, nz, d) where nx*x + ny*y + nz*z + d = 0.
    init(plane p: SIMD4<Float>) {
        a = p.x * p.x; b = p.x * p.y; c = p.x * p.z; d = p.x * p.w
        e = p.y * p.y; f = p.y * p.z; g = p.y * p.w
        h = p.z * p.z; i = p.z * p.w
        j = p.w * p.w
    }

    init(a: Float, b: Float, c: Float, d: Float, e: Float, f: Float, g: Float, h: Float, i: Float, j: Float) {
        self.a = a; self.b = b; self.c = c; self.d = d
        self.e = e; self.f = f; self.g = g
        self.h = h; self.i = i
        self.j = j
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            a: lhs.a + rhs.a, b: lhs.b + rhs.b, c: lhs.c + rhs.c, d: lhs.d + rhs.d,
            e: lhs.e + rhs.e, f: lhs.f + rhs.f, g: lhs.g + rhs.g,
            h: lhs.h + rhs.h, i: lhs.i + rhs.i,
            j: lhs.j + rhs.j
        )
    }

    static func += (lhs: inout Self, rhs: Self) {
        lhs = lhs + rhs
    }

    /// Evaluate the quadric error for a point v.
    func error(at v: SIMD3<Float>) -> Float {
        let x = v.x, y = v.y, z = v.z
        return a * x * x + 2 * b * x * y + 2 * c * x * z + 2 * d * x
             + e * y * y + 2 * f * y * z + 2 * g * y
             + h * z * z + 2 * i * z
             + j
    }

    /// Find the point that minimizes the quadric error.
    /// Returns nil if the 3×3 sub-matrix is singular (falls back to midpoint).
    func optimalPosition() -> SIMD3<Float>? {
        // Solve the upper-left 3×3 of the quadric derivative = 0
        let mat = simd_float3x3(
            SIMD3(a, b, c),
            SIMD3(b, e, f),
            SIMD3(c, f, h)
        )
        let det = mat.determinant
        guard abs(det) > 1e-10 else {
            return nil
        }
        let rhs = SIMD3(-d, -g, -i)
        return mat.inverse * rhs
    }
}

// MARK: - Heap

/// A min-heap for edge collapse candidates, keyed by error cost.
private struct CollapseHeap {
    struct Entry: Comparable {
        let cost: Float
        let halfEdge: HalfEdgeTopology.HalfEdgeID
        let generation: Int // to detect stale entries

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.cost < rhs.cost
        }
    }

    private var storage: [Entry] = []

    var isEmpty: Bool { storage.isEmpty }

    mutating func insert(_ entry: Entry) {
        storage.append(entry)
        siftUp(storage.count - 1)
    }

    mutating func removeMin() -> Entry? {
        guard !storage.isEmpty else {
            return nil
        }
        if storage.count == 1 {
            return storage.removeLast()
        }
        let min = storage[0]
        storage[0] = storage.removeLast()
        siftDown(0)
        return min
    }

    private mutating func siftUp(_ index: Int) {
        var i = index
        while i > 0 {
            let parent = (i - 1) / 2
            if storage[i] < storage[parent] {
                storage.swapAt(i, parent)
                i = parent
            } else {
                break
            }
        }
    }

    private mutating func siftDown(_ index: Int) {
        var i = index
        let count = storage.count
        while true {
            let left = 2 * i + 1
            let right = 2 * i + 2
            var smallest = i
            if left < count, storage[left] < storage[smallest] {
                smallest = left
            }
            if right < count, storage[right] < storage[smallest] {
                smallest = right
            }
            if smallest == i {
                break
            }
            storage.swapAt(i, smallest)
            i = smallest
        }
    }
}

// MARK: - Mesh decimation

public extension Mesh {
    /// Simplify the mesh by reducing face count using Quadric Error Metrics.
    ///
    /// - Parameter targetFaceCount: The desired number of faces. The algorithm stops
    ///   when this count is reached or no more edges can be collapsed.
    /// - Returns: A new simplified mesh.
    func decimated(targetFaceCount: Int) -> Mesh {
        var result = self
        result.decimate(targetFaceCount: targetFaceCount)
        return result
    }

    /// Simplify the mesh in place by reducing face count using Quadric Error Metrics.
    ///
    /// - Parameter targetFaceCount: The desired number of faces. The algorithm stops
    ///   when this count is reached or no more edges can be collapsed.
    mutating func decimate(targetFaceCount: Int) {
        let vertexCount = topology.vertices.count

        // 1. Compute initial quadrics per vertex
        var quadrics = [Quadric](repeating: .zero, count: vertexCount)
        for face in topology.faces where face.edge != nil {
            let verts = topology.vertexLoop(for: face.id)
            guard verts.count >= 3 else {
                continue
            }
            // Compute face plane
            let p0 = positions[verts[0].raw]
            let p1 = positions[verts[1].raw]
            let p2 = positions[verts[2].raw]
            let edge1 = p1 - p0
            let edge2 = p2 - p0
            var normal = simd_cross(edge1, edge2)
            let len = simd_length(normal)
            if len < 1e-10 {
                continue
            }
            normal /= len
            let d = -simd_dot(normal, p0)
            let plane = SIMD4<Float>(normal.x, normal.y, normal.z, d)
            let q = Quadric(plane: plane)
            for v in verts {
                quadrics[v.raw] += q
            }
        }

        // 2. Generation counter per vertex (to invalidate stale heap entries)
        var generation = [Int](repeating: 0, count: vertexCount)

        // 3. Compute collapse cost for an edge
        func collapseCost(heID: HalfEdgeTopology.HalfEdgeID) -> (cost: Float, position: SIMD3<Float>)? {
            let origin = topology.halfEdges[heID.raw].origin
            guard let dest = topology.destViaNext(of: heID) else {
                return nil
            }
            let combined = quadrics[origin.raw] + quadrics[dest.raw]
            let optimal = combined.optimalPosition()
            let pos: SIMD3<Float>
            if let optimal {
                pos = optimal
            } else {
                // Fallback: midpoint
                pos = (positions[origin.raw] + positions[dest.raw]) * 0.5
            }
            let cost = max(combined.error(at: pos), 0)
            return (cost, pos)
        }

        // 4. Build initial heap
        var heap = CollapseHeap()
        var seenEdges = Set<Int>()
        for he in topology.halfEdges where he.next != nil {
            // Deduplicate: only insert one direction per undirected edge
            let o = he.origin.raw
            guard let d = topology.destViaNext(of: he.id)?.raw else {
                continue
            }
            let key = min(o, d) * vertexCount + max(o, d)
            guard seenEdges.insert(key).inserted else {
                continue
            }
            if let (cost, _) = collapseCost(heID: he.id) {
                heap.insert(.init(cost: cost, halfEdge: he.id, generation: generation[o]))
            }
        }

        // 5. Iteratively collapse cheapest edge
        var currentFaceCount = topology.faces.filter { $0.edge != nil }.count

        while currentFaceCount > targetFaceCount {
            guard let entry = heap.removeMin() else {
                break
            }

            let he = topology.halfEdges[entry.halfEdge.raw]

            // Skip stale entries (tombstoned half-edges)
            guard he.next != nil else {
                continue
            }

            let origin = he.origin
            guard let dest = topology.destViaNext(of: entry.halfEdge) else {
                continue
            }

            // Skip if generation doesn't match (vertex was already modified)
            if entry.generation != generation[origin.raw] {
                continue
            }

            // Compute optimal position for the collapse
            let combined = quadrics[origin.raw] + quadrics[dest.raw]
            let newPos: SIMD3<Float>
            if let optimal = combined.optimalPosition() {
                newPos = optimal
            } else {
                newPos = (positions[origin.raw] + positions[dest.raw]) * 0.5
            }

            // Count faces that will be removed (adjacent to the edge)
            var facesRemoved = 0
            if he.face != nil {
                facesRemoved += 1
            }
            if let twinID = he.twin, topology.halfEdges[twinID.raw].face != nil {
                facesRemoved += 1
            }

            // Perform the collapse
            guard let survivor = topology.collapseEdge(entry.halfEdge) else {
                continue
            }

            currentFaceCount -= facesRemoved

            // Update position and quadric of survivor
            positions[survivor.raw] = newPos
            quadrics[survivor.raw] = combined

            // Bump generation for the survivor
            generation[survivor.raw] += 1

            // Re-insert edges around the survivor into the heap
            for neighborHE in topology.halfEdges where neighborHE.next != nil && neighborHE.origin == survivor {
                if let (cost, _) = collapseCost(heID: neighborHE.id) {
                    heap.insert(.init(cost: cost, halfEdge: neighborHE.id, generation: generation[survivor.raw]))
                }
            }
        }
    }

    /// Simplify the mesh by removing a ratio of faces.
    ///
    /// - Parameter ratio: The fraction of faces to keep (0.0–1.0).
    ///   For example, 0.5 keeps roughly half the faces.
    /// - Returns: A new simplified mesh.
    func decimated(ratio: Float) -> Mesh {
        let currentCount = topology.faces.filter { $0.edge != nil }.count
        let target = max(1, Int(Float(currentCount) * ratio))
        return decimated(targetFaceCount: target)
    }
}
