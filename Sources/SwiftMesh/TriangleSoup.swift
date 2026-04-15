import simd

/// A flat indexed-triangle representation used as an intermediate format for
/// CSG and other whole-mesh operations.
///
/// Positions are stored in a shared array; triangles reference them by index.
/// Duplicate positions can be merged via ``welded(tolerance:)``.
///
/// Convert to and from ``Mesh`` with ``init(mesh:)`` and ``toMesh(weldTolerance:)``.
/// When converting from a mesh, all submeshes are merged into one and per-corner
/// attributes (normals, UVs, tangents, colors) are discarded.
public struct TriangleSoup: Sendable, Equatable {
    /// All vertex positions (may contain duplicates).
    public var positions: [SIMD3<Float>]

    /// Triangles as index triples into ``positions``.
    public var triangles: [(Int, Int, Int)]

    public init(positions: [SIMD3<Float>] = [], triangles: [(Int, Int, Int)] = []) {
        self.positions = positions
        self.triangles = triangles
    }

    /// Number of triangles.
    public var triangleCount: Int { triangles.count }

    /// Number of positions (including potential duplicates).
    public var positionCount: Int { positions.count }

    // MARK: - Mutation

    /// Append a single triangle by its three vertex positions.
    ///
    /// Three new positions are appended and a new triangle referencing them is added.
    ///
    /// - Parameters:
    ///   - a: The first vertex position.
    ///   - b: The second vertex position.
    ///   - c: The third vertex position.
    /// - Returns: The index of the newly added triangle.
    @discardableResult
    public mutating func addTriangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> Int {
        let base = positions.count
        positions.append(contentsOf: [a, b, c])
        let idx = triangles.count
        triangles.append((base, base + 1, base + 2))
        return idx
    }

    /// Append all triangles from another soup.
    ///
    /// Positions are concatenated and triangle indices are offset so they
    /// reference the correct positions in the combined array.
    public mutating func append(_ other: Self) {
        let offset = positions.count
        positions.append(contentsOf: other.positions)
        for (a, b, c) in other.triangles {
            triangles.append((a + offset, b + offset, c + offset))
        }
    }

    // MARK: - Welding

    /// Returns a new soup with near-duplicate positions merged.
    ///
    /// Positions within `tolerance` distance of each other are collapsed to a
    /// single position. Triangle indices are remapped accordingly.
    /// Uses spatial hashing for O(n) expected performance.
    ///
    /// - Parameter tolerance: Maximum distance between positions to consider
    ///   them duplicates. Defaults to `1e-5`.
    /// - Returns: A new soup with deduplicated positions.
    public func welded(tolerance: Float = 1e-5) -> Self {
        guard !positions.isEmpty else {
            return self
        }

        let cellSize = max(tolerance * 2, 1e-7)
        let invCell = 1.0 / cellSize

        // Spatial hash → list of (newIndex, position)
        var buckets: [SIMD3<Int32>: [(Int, SIMD3<Float>)]] = [:]
        var remap = [Int](repeating: 0, count: positions.count)
        var newPositions: [SIMD3<Float>] = []

        for (oldIdx, pos) in positions.enumerated() {
            let cell = SIMD3<Int32>(
                Int32(floor(pos.x * invCell)),
                Int32(floor(pos.y * invCell)),
                Int32(floor(pos.z * invCell))
            )

            var found = false
            // Search neighboring cells to handle positions near cell boundaries
            outer: for dx: Int32 in -1...1 {
                for dy: Int32 in -1...1 {
                    for dz: Int32 in -1...1 {
                        let neighbor = cell &+ SIMD3<Int32>(dx, dy, dz)
                        if let bucket = buckets[neighbor] {
                            for (newIdx, existing) in bucket {
                                if simd_distance(pos, existing) <= tolerance {
                                    remap[oldIdx] = newIdx
                                    found = true
                                    break outer
                                }
                            }
                        }
                    }
                }
            }

            if !found {
                let newIdx = newPositions.count
                newPositions.append(pos)
                remap[oldIdx] = newIdx
                buckets[cell, default: []].append((newIdx, pos))
            }
        }

        let newTriangles = triangles.map { (remap[$0.0], remap[$0.1], remap[$0.2]) }
        return Self(positions: newPositions, triangles: newTriangles)
    }

    /// Flip the winding order of all triangles in place.
    ///
    /// Swaps the second and third index of every triangle, reversing
    /// face orientation.
    public mutating func flipAll() {
        triangles = triangles.map { ($0.0, $0.2, $0.1) }
    }

    /// Returns a copy with all triangle windings flipped.
    ///
    /// - Returns: A new soup with reversed face orientation.
    public func flipped() -> Self {
        var copy = self
        copy.flipAll()
        return copy
    }
}

// MARK: - Mesh conversions

public extension TriangleSoup {
    /// Creates a triangle soup from a mesh by triangulating all faces.
    ///
    /// All faces are triangulated regardless of which submesh they belong to;
    /// submesh boundaries are not preserved. Per-corner attributes (normals,
    /// UVs, tangents, colors) are discarded — only positions and connectivity
    /// are retained.
    ///
    /// - Parameter mesh: The source mesh to convert.
    init(mesh: Mesh) {
        let tris = mesh.triangulate()
        self.positions = mesh.positions
        self.triangles = tris.map { ($0.0.raw, $0.1.raw, $0.2.raw) }
    }

    /// Converts back to a ``Mesh``, welding duplicate positions first.
    ///
    /// Degenerate triangles (where welding collapses two or more vertices)
    /// are silently removed. The resulting mesh has only positions and
    /// topology — per-corner attributes (normals, UVs, tangents, colors)
    /// are not set, and a single default submesh is created.
    ///
    /// - Parameter weldTolerance: Maximum distance for merging positions.
    ///   Defaults to `1e-5`.
    /// - Returns: A new ``Mesh`` built from the welded triangle data.
    func toMesh(weldTolerance: Float = 1e-5) -> Mesh {
        let welded = welded(tolerance: weldTolerance)

        // Filter degenerate triangles (where two or more indices are the same after welding)
        let validTriangles = welded.triangles.filter { $0.0 != $0.1 && $0.1 != $0.2 && $0.0 != $0.2 }

        let faces = validTriangles.map { [$0.0, $0.1, $0.2] }
        return Mesh(positions: welded.positions, faces: faces)
    }
}

// MARK: - Equatable conformance for tuple arrays

extension TriangleSoup {
    public static func == (lhs: TriangleSoup, rhs: TriangleSoup) -> Bool {
        guard lhs.positions == rhs.positions else {
            return false
        }
        guard lhs.triangles.count == rhs.triangles.count else {
            return false
        }
        for (l, r) in zip(lhs.triangles, rhs.triangles) {
            if l.0 != r.0 || l.1 != r.1 || l.2 != r.2 {
                return false
            }
        }
        return true
    }
}
