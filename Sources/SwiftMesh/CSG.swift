import simd

// MARK: - CSG Plane

/// A plane in 3D space defined by a normal and distance from origin.
struct CSGPlane: Sendable {
    var normal: SIMD3<Float>
    var w: Float // dot(normal, pointOnPlane)

    init(normal: SIMD3<Float>, w: Float) {
        self.normal = normal
        self.w = w
    }

    /// Build a plane from three points (counter-clockwise winding).
    init?(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
        let n = simd_cross(b - a, c - a)
        let len = simd_length(n)
        guard len > 1e-10 else {
            return nil
        }
        self.normal = n / len
        self.w = simd_dot(self.normal, a)
    }

    /// Signed distance from a point to this plane.
    func distanceTo(_ point: SIMD3<Float>) -> Float {
        simd_dot(normal, point) - w
    }

    func flipped() -> Self {
        Self(normal: -normal, w: -w)
    }
}

// MARK: - CSG Polygon

/// A convex polygon used internally by the BSP tree.
struct CSGPolygon: Sendable {
    var vertices: [SIMD3<Float>]
    var plane: CSGPlane

    init(vertices: [SIMD3<Float>], plane: CSGPlane) {
        self.vertices = vertices
        self.plane = plane
    }

    init?(vertices: [SIMD3<Float>]) {
        guard vertices.count >= 3 else {
            return nil
        }
        guard let plane = CSGPlane(vertices[0], vertices[1], vertices[2]) else {
            return nil
        }
        self.vertices = vertices
        self.plane = plane
    }

    func flipped() -> Self {
        Self(vertices: vertices.reversed(), plane: plane.flipped())
    }
}

// MARK: - BSP Node

/// A BSP tree node for CSG operations.
///
/// Based on the algorithm described in "Merging BSP Trees Yields Polyhedral
/// Set Operations" and popularized by the csg.js library.
final class CSGNode: @unchecked Sendable {
    var plane: CSGPlane?
    var front: CSGNode?
    var back: CSGNode?
    var polygons: [CSGPolygon]

    init(polygons: [CSGPolygon] = []) {
        self.polygons = []
        if !polygons.isEmpty {
            build(polygons)
        }
    }

    /// Clone this BSP tree.
    func clone() -> CSGNode {
        let node = CSGNode()
        node.plane = plane
        node.front = front?.clone()
        node.back = back?.clone()
        node.polygons = polygons
        return node
    }

    /// Invert all polygons and flip the BSP tree (inside ↔ outside).
    func invert() {
        for i in polygons.indices {
            polygons[i] = polygons[i].flipped()
        }
        plane = plane?.flipped()
        front?.invert()
        back?.invert()
        swap(&front, &back)
    }

    /// Recursively remove all polygons in `polygons` that are inside this BSP tree.
    func clipPolygons(_ list: [CSGPolygon]) -> [CSGPolygon] {
        guard let plane else {
            return list
        }

        var frontList: [CSGPolygon] = []
        var backList: [CSGPolygon] = []
        var coplanarFrontList: [CSGPolygon] = []
        var coplanarBackList: [CSGPolygon] = []

        for polygon in list {
            splitPolygon(polygon, plane: plane, front: &frontList, back: &backList, coplanarFront: &coplanarFrontList, coplanarBack: &coplanarBackList)
        }

        frontList.append(contentsOf: coplanarFrontList)
        backList.append(contentsOf: coplanarBackList)

        frontList = front?.clipPolygons(frontList) ?? frontList
        backList = back?.clipPolygons(backList) ?? []

        return frontList + backList
    }

    /// Remove all polygons in this tree that are inside the other BSP tree.
    func clipTo(_ other: CSGNode) {
        polygons = other.clipPolygons(polygons)
        front?.clipTo(other)
        back?.clipTo(other)
    }

    /// Return all polygons in this BSP tree.
    func allPolygons() -> [CSGPolygon] {
        var result = polygons
        if let front {
            result.append(contentsOf: front.allPolygons())
        }
        if let back {
            result.append(contentsOf: back.allPolygons())
        }
        return result
    }

    /// Build a BSP tree from a list of polygons. Called on a fresh or existing node.
    func build(_ list: [CSGPolygon]) {
        guard !list.isEmpty else {
            return
        }

        if plane == nil {
            plane = list[0].plane
        }

        var frontList: [CSGPolygon] = []
        var backList: [CSGPolygon] = []

        var coplanarFrontList: [CSGPolygon] = []
        var coplanarBackList: [CSGPolygon] = []
        for polygon in list {
            splitPolygon(polygon, plane: plane!, front: &frontList, back: &backList, coplanarFront: &coplanarFrontList, coplanarBack: &coplanarBackList)
        }
        polygons.append(contentsOf: coplanarFrontList)
        polygons.append(contentsOf: coplanarBackList)

        if !frontList.isEmpty {
            if front == nil {
                front = CSGNode()
            }
            front!.build(frontList)
        }

        if !backList.isEmpty {
            if back == nil {
                back = CSGNode()
            }
            back!.build(backList)
        }
    }
}

// MARK: - Polygon Splitting

private let epsilon: Float = 1e-5

private enum PointClassification: Int {
    case coplanar = 0
    case front = 1
    case back = 2
    case spanning = 3 // only used for polygon classification
}

/// Split a polygon by a plane, distributing results into the appropriate lists.
private func splitPolygon(
    _ polygon: CSGPolygon,
    plane: CSGPlane,
    front: inout [CSGPolygon],
    back: inout [CSGPolygon],
    coplanarFront: inout [CSGPolygon],
    coplanarBack: inout [CSGPolygon]
) {
    // Classify each vertex
    var types: [PointClassification] = []
    var polygonType: Int = 0

    for vertex in polygon.vertices {
        let t = plane.distanceTo(vertex)
        let type: PointClassification
        if t < -epsilon {
            type = .back
        } else if t > epsilon {
            type = .front
        } else {
            type = .coplanar
        }
        polygonType |= type.rawValue
        types.append(type)
    }

    switch PointClassification(rawValue: polygonType) ?? .spanning {
    case .coplanar:
        if simd_dot(plane.normal, polygon.plane.normal) > 0 {
            coplanarFront.append(polygon)
        } else {
            coplanarBack.append(polygon)
        }

    case .front:
        front.append(polygon)

    case .back:
        back.append(polygon)

    case .spanning:
        var frontVerts: [SIMD3<Float>] = []
        var backVerts: [SIMD3<Float>] = []

        for i in 0..<polygon.vertices.count {
            let j = (i + 1) % polygon.vertices.count
            let ti = types[i]
            let tj = types[j]
            let vi = polygon.vertices[i]
            let vj = polygon.vertices[j]

            if ti != .back {
                frontVerts.append(vi)
            }
            if ti != .front {
                backVerts.append(vi)
            }

            if (ti.rawValue | tj.rawValue) == PointClassification.spanning.rawValue {
                // Edge crosses the plane — compute intersection point
                let t = (plane.w - simd_dot(plane.normal, vi)) / simd_dot(plane.normal, vj - vi)
                let intersection = vi + (vj - vi) * t
                frontVerts.append(intersection)
                backVerts.append(intersection)
            }
        }

        if frontVerts.count >= 3 {
            if let poly = CSGPolygon(vertices: frontVerts) {
                front.append(poly)
            }
        }
        if backVerts.count >= 3 {
            if let poly = CSGPolygon(vertices: backVerts) {
                back.append(poly)
            }
        }
    }
}

// MARK: - CSG Operations on TriangleSoup

/// The type of CSG (Constructive Solid Geometry) boolean operation.
public enum CSGOperation: Sendable {
    /// Combine two volumes into one (A ∪ B).
    case union
    /// Keep only the overlapping volume (A ∩ B).
    case intersection
    /// Subtract the second volume from the first (A − B).
    case difference
}

public extension TriangleSoup {
    /// Performs a CSG boolean operation combining this soup with another.
    ///
    /// Both soups are interpreted as closed triangle meshes defining solid
    /// volumes. The operation is computed via a BSP tree algorithm.
    ///
    /// - Parameters:
    ///   - operation: The boolean operation to perform.
    ///   - other: The second operand.
    /// - Returns: A new triangle soup representing the result.
    func csg(_ operation: CSGOperation, _ other: TriangleSoup) -> TriangleSoup {
        let polygonsA = self.toPolygons()
        let polygonsB = other.toPolygons()

        guard !polygonsA.isEmpty, !polygonsB.isEmpty else {
            switch operation {
            case .union:
                return polygonsA.isEmpty ? other : self

            case .intersection:
                return Self()

            case .difference:
                return polygonsA.isEmpty ? Self() : self
            }
        }

        let a = CSGNode(polygons: polygonsA)
        let b = CSGNode(polygons: polygonsB)

        let resultPolygons: [CSGPolygon]

        switch operation {
        case .union:
            // A ∪ B = ~(~A ∩ ~B)
            // Clip A to B, clip B to A, remove coplanar overlaps, combine
            a.clipTo(b)
            b.clipTo(a)
            b.invert()
            b.clipTo(a)
            b.invert()
            a.build(b.allPolygons())
            resultPolygons = a.allPolygons()

        case .intersection:
            // A ∩ B
            // Invert both, union the inversions, invert result
            a.invert()
            b.clipTo(a)
            b.invert()
            a.clipTo(b)
            b.clipTo(a)
            a.build(b.allPolygons())
            a.invert()
            resultPolygons = a.allPolygons()

        case .difference:
            // A - B = A ∩ ~B
            a.invert()
            a.clipTo(b)
            b.clipTo(a)
            b.invert()
            b.clipTo(a)
            b.invert()
            a.build(b.allPolygons())
            a.invert()
            resultPolygons = a.allPolygons()
        }

        return TriangleSoup.fromPolygons(resultPolygons)
    }

    /// Returns the union of this soup with another (A ∪ B).
    ///
    /// The result contains the combined volume of both inputs.
    ///
    /// - Parameter other: The second operand.
    /// - Returns: A new triangle soup representing the union.
    func union(_ other: TriangleSoup) -> TriangleSoup {
        csg(.union, other)
    }

    /// Returns the intersection of this soup with another (A ∩ B).
    ///
    /// The result contains only the volume shared by both inputs.
    ///
    /// - Parameter other: The second operand.
    /// - Returns: A new triangle soup representing the intersection.
    func intersection(_ other: TriangleSoup) -> TriangleSoup {
        csg(.intersection, other)
    }

    /// Returns the difference of this soup minus another (A − B).
    ///
    /// The result contains the volume of the first input with the second
    /// input's volume carved out.
    ///
    /// - Parameter other: The volume to subtract.
    /// - Returns: A new triangle soup representing the difference.
    func difference(_ other: TriangleSoup) -> TriangleSoup {
        csg(.difference, other)
    }
}

// MARK: - Polygon ↔ TriangleSoup conversion

extension TriangleSoup {
    /// Convert triangles to CSG polygons.
    func toPolygons() -> [CSGPolygon] {
        triangles.compactMap { tri in
            let a = positions[tri.0]
            let b = positions[tri.1]
            let c = positions[tri.2]
            return CSGPolygon(vertices: [a, b, c])
        }
    }

    /// Build a triangle soup from CSG polygons by fan-triangulating each polygon.
    static func fromPolygons(_ polygons: [CSGPolygon]) -> TriangleSoup {
        var soup = TriangleSoup()
        for polygon in polygons {
            guard polygon.vertices.count >= 3 else {
                continue
            }
            // Fan triangulation from vertex 0
            let base = soup.positions.count
            soup.positions.append(contentsOf: polygon.vertices)
            for i in 1..<(polygon.vertices.count - 1) {
                soup.triangles.append((base, base + i, base + i + 1))
            }
        }
        return soup
    }
}

// MARK: - Mesh CSG API

public extension Mesh {
    /// Returns the CSG union of this mesh with another (A ∪ B).
    ///
    /// Both meshes are triangulated, combined via a BSP-tree algorithm, and
    /// the result is rebuilt into a new mesh. Per-corner attributes (normals,
    /// UVs, tangents, colors) are not preserved, and all submeshes are merged
    /// into one.
    ///
    /// - Parameter other: The mesh to union with.
    /// - Returns: A new mesh representing the combined volume.
    func union(_ other: Mesh, mergeCoplanar: Bool = true) -> Mesh {
        var result = TriangleSoup(mesh: self).union(TriangleSoup(mesh: other)).toMesh()
        if mergeCoplanar { result = result.mergingCoplanarFaces() }
        return result
    }

    /// Returns the CSG intersection of this mesh with another (A ∩ B).
    ///
    /// Both meshes are triangulated, combined via a BSP-tree algorithm, and
    /// the result is rebuilt into a new mesh. Per-corner attributes (normals,
    /// UVs, tangents, colors) are not preserved, and all submeshes are merged
    /// into one.
    ///
    /// - Parameter other: The mesh to intersect with.
    /// - Returns: A new mesh containing only the shared volume.
    func intersection(_ other: Mesh, mergeCoplanar: Bool = true) -> Mesh {
        var result = TriangleSoup(mesh: self).intersection(TriangleSoup(mesh: other)).toMesh()
        if mergeCoplanar { result = result.mergingCoplanarFaces() }
        return result
    }

    /// Returns the CSG difference of this mesh minus another (A − B).
    ///
    /// Both meshes are triangulated, combined via a BSP-tree algorithm, and
    /// the result is rebuilt into a new mesh. Per-corner attributes (normals,
    /// UVs, tangents, colors) are not preserved, and all submeshes are merged
    /// into one.
    ///
    /// - Parameter other: The mesh volume to subtract.
    /// - Returns: A new mesh with the other's volume carved out.
    func difference(_ other: Mesh, mergeCoplanar: Bool = true) -> Mesh {
        var result = TriangleSoup(mesh: self).difference(TriangleSoup(mesh: other)).toMesh()
        if mergeCoplanar { result = result.mergingCoplanarFaces() }
        return result
    }
}
