import simd

// MARK: - Convex Hull

public extension Mesh {
    /// Compute the convex hull of a set of 3D points, returning a ``Mesh``.
    ///
    /// Uses an incremental convex hull algorithm. The resulting mesh is a closed
    /// convex polyhedron with triangular faces and outward-facing normals.
    ///
    /// - Parameters:
    ///   - points: The input points. At least 4 non-coplanar points are required.
    ///   - attributes: Which attributes to generate on the resulting mesh.
    /// - Returns: A convex hull mesh, or `nil` if the points are degenerate
    ///   (fewer than 4 points, or all coplanar/collinear/coincident).
    static func convexHull(of points: [SIMD3<Float>], attributes: MeshAttributes = .default) -> Mesh? {
        guard let hull = ConvexHullBuilder(points: points) else {
            return nil
        }
        var mesh = hull.toMesh()
        mesh.applyAttributes(attributes)
        return mesh
    }
}

// MARK: - ConvexHullBuilder

/// Incremental convex hull construction for 3D point sets.
///
/// Builds the hull by starting from an initial tetrahedron and adding points
/// one at a time, updating the hull at each step.
private struct ConvexHullBuilder {
    /// Deduplicated positions used by the hull.
    var positions: [SIMD3<Float>]

    /// Triangular faces as index triples (CCW winding, outward-facing).
    var faces: [(Int, Int, Int)]

    /// Build the convex hull of `points`, or return `nil` if degenerate.
    init?(points: [SIMD3<Float>]) {
        guard points.count >= 4 else {
            return nil
        }

        self.positions = points
        self.faces = []

        // --- Find initial tetrahedron ---
        guard let seed = Self.findInitialTetrahedron(points) else {
            return nil
        }

        let (i0, i1, i2, i3) = seed

        // Orient so that the fourth point is "above" the first triangle
        // (i.e., the triangle (i0,i1,i2) has its outward normal pointing away from i3).
        let normal012 = simd_cross(points[i1] - points[i0], points[i2] - points[i0])
        let dot = simd_dot(normal012, points[i3] - points[i0])

        if dot > 0 {
            // i3 is on the positive side — flip the triangle so normal points outward (away from i3)
            faces = [
                (i0, i2, i1),
                (i0, i1, i3),
                (i1, i2, i3),
                (i0, i3, i2)
            ]
        } else {
            faces = [
                (i0, i1, i2),
                (i0, i3, i1),
                (i1, i3, i2),
                (i0, i2, i3)
            ]
        }

        // --- Incrementally add remaining points ---
        let seedSet: Set<Int> = [i0, i1, i2, i3]
        for idx in points.indices where !seedSet.contains(idx) {
            addPoint(idx)
        }
    }

    /// Convert the hull into a ``Mesh``.
    func toMesh() -> Mesh {
        // Collect which positions are actually used
        var usedSet = Set<Int>()
        for (a, b, c) in faces {
            usedSet.insert(a)
            usedSet.insert(b)
            usedSet.insert(c)
        }

        let usedSorted = usedSet.sorted()
        var remap = [Int: Int]()
        var newPositions: [SIMD3<Float>] = []
        for old in usedSorted {
            remap[old] = newPositions.count
            newPositions.append(positions[old])
        }

        let meshFaces: [[Int]] = faces.map { a, b, c in
            [remap[a]!, remap[b]!, remap[c]!]
        }

        return Mesh(positions: newPositions, faces: meshFaces)
    }

    // MARK: - Incremental insertion

    /// Add a single point to the hull. If the point is already inside or on the
    /// hull, this is a no-op.
    private mutating func addPoint(_ pointIndex: Int) {
        let p = positions[pointIndex]

        // Find all faces visible from p
        var visible = [Bool](repeating: false, count: faces.count)
        var anyVisible = false

        for (fIdx, face) in faces.enumerated() {
            let (a, b, c) = face
            let normal = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
            let d = simd_dot(normal, p - positions[a])
            if d > 1e-7 {
                visible[fIdx] = true
                anyVisible = true
            }
        }

        guard anyVisible else {
            return // point is inside or on the hull
        }

        // Find the horizon edges (edges shared between a visible and non-visible face).
        // An edge (u, v) in a visible face is a horizon edge if the twin edge (v, u)
        // belongs to a non-visible face.
        var edgeToFace: [Int64: Int] = [:] // edge key → face index

        func edgeKey(_ a: Int, _ b: Int) -> Int64 {
            Int64(a) << 32 | Int64(b & 0x7FFF_FFFF)
        }

        for (fIdx, face) in faces.enumerated() {
            let (a, b, c) = face
            edgeToFace[edgeKey(a, b)] = fIdx
            edgeToFace[edgeKey(b, c)] = fIdx
            edgeToFace[edgeKey(c, a)] = fIdx
        }

        // Collect horizon edges in order
        var horizonEdges: [(Int, Int)] = []
        for (fIdx, face) in faces.enumerated() where visible[fIdx] {
            let verts = [face.0, face.1, face.2]
            for i in 0..<3 {
                let u = verts[i]
                let v = verts[(i + 1) % 3]
                // Check if the twin edge's face is non-visible
                if let twinFace = edgeToFace[edgeKey(v, u)], !visible[twinFace] {
                    horizonEdges.append((u, v))
                }
            }
        }

        // Remove visible faces
        var newFaces: [(Int, Int, Int)] = []
        for (fIdx, face) in faces.enumerated() where !visible[fIdx] {
            newFaces.append(face)
        }

        // Create new faces connecting the horizon edges to the new point
        for (u, v) in horizonEdges {
            newFaces.append((u, v, pointIndex))
        }

        faces = newFaces
    }

    // MARK: - Initial tetrahedron

    /// Find 4 non-coplanar points to seed the hull, or return nil if all points
    /// are degenerate (coplanar, collinear, or coincident).
    static func findInitialTetrahedron(_ points: [SIMD3<Float>]) -> (Int, Int, Int, Int)? {
        guard points.count >= 4 else {
            return nil
        }

        // Find two distinct points (maximally separated along some axis for robustness)
        let i0 = 0
        var i1 = -1
        var maxDist: Float = 0
        for i in 1..<points.count {
            let d = simd_distance_squared(points[i0], points[i])
            if d > maxDist {
                maxDist = d
                i1 = i
            }
        }
        guard i1 >= 0, maxDist > 1e-14 else {
            return nil
        }

        // Find a third point maximally distant from the line (i0, i1)
        let lineDir = simd_normalize(points[i1] - points[i0])
        var i2 = -1
        var maxLineDist: Float = 0
        for i in 0..<points.count where i != i0 && i != i1 {
            let v = points[i] - points[i0]
            let proj = simd_dot(v, lineDir)
            let perpendicular = v - lineDir * proj
            let d = simd_length_squared(perpendicular)
            if d > maxLineDist {
                maxLineDist = d
                i2 = i
            }
        }
        guard i2 >= 0, maxLineDist > 1e-14 else {
            return nil // collinear
        }

        // Find a fourth point maximally distant from the plane (i0, i1, i2)
        let planeNormal = simd_normalize(simd_cross(points[i1] - points[i0], points[i2] - points[i0]))
        var i3 = -1
        var maxPlaneDist: Float = 0
        for i in 0..<points.count where i != i0 && i != i1 && i != i2 {
            let d = abs(simd_dot(points[i] - points[i0], planeNormal))
            if d > maxPlaneDist {
                maxPlaneDist = d
                i3 = i
            }
        }
        guard i3 >= 0, maxPlaneDist > 1e-7 else {
            return nil // coplanar
        }

        return (i0, i1, i2, i3)
    }
}
