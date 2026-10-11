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

    /// Triangular faces as index triples (CCW winding, outward-facing). Includes removed faces; see `alive`.
    var faces: [(Int, Int, Int)]
    var alive: [Bool] = []
    /// Directed edge → live face containing it.
    var edgeToFace: [Int64: Int] = [:]
    /// Unprocessed points that see each face.
    var faceConflicts: [[Int]] = []
    /// One face each unprocessed point sees, or -1 if it is inside the hull.
    var pointConflict: [Int] = []

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

        let seedFaces = faces
        faces = []
        for face in seedFaces {
            appendFace(face)
        }

        // --- Assign each remaining point to a face it sees, then insert ---
        let seedSet: Set<Int> = [i0, i1, i2, i3]
        pointConflict = [Int](repeating: -1, count: points.count)
        for idx in points.indices where !seedSet.contains(idx) {
            if let face = faces.indices.first(where: { sees(idx, face: $0) }) {
                assign(idx, to: face)
            }
        }
        for idx in points.indices where !seedSet.contains(idx) {
            addPoint(idx)
        }
        faces = faces.indices.filter { alive[$0] }.map { faces[$0] }
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
    private static func edgeKey(_ a: Int, _ b: Int) -> Int64 {
        Int64(a) << 32 | Int64(b & 0x7FFF_FFFF)
    }

    private func sees(_ pointIndex: Int, face faceIndex: Int) -> Bool {
        let (a, b, c) = faces[faceIndex]
        let normal = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
        return simd_dot(normal, positions[pointIndex] - positions[a]) > 1e-7
    }

    private mutating func assign(_ pointIndex: Int, to faceIndex: Int) {
        pointConflict[pointIndex] = faceIndex
        faceConflicts[faceIndex].append(pointIndex)
    }

    @discardableResult
    private mutating func appendFace(_ face: (Int, Int, Int)) -> Int {
        let index = faces.count
        faces.append(face)
        alive.append(true)
        faceConflicts.append([])
        edgeToFace[Self.edgeKey(face.0, face.1)] = index
        edgeToFace[Self.edgeKey(face.1, face.2)] = index
        edgeToFace[Self.edgeKey(face.2, face.0)] = index
        return index
    }

    private mutating func removeFace(_ index: Int) {
        alive[index] = false
        let (a, b, c) = faces[index]
        for key in [Self.edgeKey(a, b), Self.edgeKey(b, c), Self.edgeKey(c, a)] where edgeToFace[key] == index {
            edgeToFace[key] = nil
        }
    }

    private mutating func addPoint(_ pointIndex: Int) {
        let start = pointConflict[pointIndex]
        guard start >= 0 else {
            return // point is inside or on the hull
        }
        pointConflict[pointIndex] = -1

        // Flood-fill the visible region from the conflict face.
        var visible: Set<Int> = [start]
        var stack = [start]
        while let faceIndex = stack.popLast() {
            let (a, b, c) = faces[faceIndex]
            for (u, v) in [(a, b), (b, c), (c, a)] {
                if let twin = edgeToFace[Self.edgeKey(v, u)], !visible.contains(twin), sees(pointIndex, face: twin) {
                    visible.insert(twin)
                    stack.append(twin)
                }
            }
        }

        // Horizon: edges of visible faces whose twin face is not visible.
        var horizonEdges: [(Int, Int)] = []
        for faceIndex in visible {
            let (a, b, c) = faces[faceIndex]
            for (u, v) in [(a, b), (b, c), (c, a)] {
                if let twin = edgeToFace[Self.edgeKey(v, u)], !visible.contains(twin) {
                    horizonEdges.append((u, v))
                }
            }
        }

        var orphans: [Int] = []
        for faceIndex in visible {
            orphans += faceConflicts[faceIndex]
            faceConflicts[faceIndex] = []
            removeFace(faceIndex)
        }

        let newFaces = horizonEdges.map { u, v in appendFace((u, v, pointIndex)) }

        // Reassign points that saw a removed face; fall back to a full scan if no new face is visible.
        for orphan in orphans where orphan != pointIndex && pointConflict[orphan] >= 0 {
            pointConflict[orphan] = -1
            if let face = newFaces.first(where: { sees(orphan, face: $0) }) ?? faces.indices.first(where: { alive[$0] && sees(orphan, face: $0) }) {
                assign(orphan, to: face)
            }
        }
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
