import Foundation
import simd

/// Scalar type for BSP internals. Double limits vertex drift from repeated plane splits; inputs and outputs stay Float.
typealias CSGScalar = Double

// MARK: - AABB

/// Axis-aligned bounding box used for early-out tests in the BSP tree.
struct AABB: Sendable {
    var min: SIMD3<CSGScalar>
    var max: SIMD3<CSGScalar>

    init() {
        self.min = SIMD3<CSGScalar>(repeating: .infinity)
        self.max = SIMD3<CSGScalar>(repeating: -.infinity)
    }

    init(min: SIMD3<CSGScalar>, max: SIMD3<CSGScalar>) {
        self.min = min
        self.max = max
    }

    var isEmpty: Bool {
        min.x > max.x
    }

    mutating func expandToInclude(_ point: SIMD3<CSGScalar>) {
        self.min = simd_min(self.min, point)
        self.max = simd_max(self.max, point)
    }

    mutating func expandToInclude(_ other: Self) {
        self.min = simd_min(self.min, other.min)
        self.max = simd_max(self.max, other.max)
    }

    func expanded(by amount: CSGScalar) -> Self {
        Self(min: min - amount, max: max + amount)
    }

    func overlaps(_ other: Self) -> Bool {
        min.x <= other.max.x && max.x >= other.min.x &&
            min.y <= other.max.y && max.y >= other.min.y &&
            min.z <= other.max.z && max.z >= other.min.z
    }
}

extension AABB {
    init(vertices: [SIMD3<CSGScalar>]) {
        self.init()
        for v in vertices {
            expandToInclude(v)
        }
    }
}

// MARK: - CSG Plane

/// A plane in 3D space defined by a normal and distance from origin.
struct CSGPlane: Sendable {
    var normal: SIMD3<CSGScalar>
    var w: CSGScalar // dot(normal, pointOnPlane)

    init(normal: SIMD3<CSGScalar>, w: CSGScalar) {
        self.normal = normal
        self.w = w
    }

    /// Build a plane from three points (counter-clockwise winding).
    init?(_ a: SIMD3<CSGScalar>, _ b: SIMD3<CSGScalar>, _ c: SIMD3<CSGScalar>) {
        let n = simd_cross(b - a, c - a)
        let len = simd_length(n)
        guard len > 1e-10 else {
            return nil
        }
        self.normal = n / len
        self.w = simd_dot(self.normal, a)
    }

    /// Signed distance from a point to this plane.
    func distanceTo(_ point: SIMD3<CSGScalar>) -> CSGScalar {
        simd_dot(normal, point) - w
    }

    func flipped() -> Self {
        Self(normal: -normal, w: -w)
    }
}

// MARK: - CSG Polygon

/// A convex polygon used internally by the BSP tree.
struct CSGPolygon: Sendable {
    let vertices: [SIMD3<CSGScalar>]
    var plane: CSGPlane
    let bounds: AABB

    init(vertices: [SIMD3<CSGScalar>], plane: CSGPlane) {
        self.init(vertices: vertices, plane: plane, bounds: AABB(vertices: vertices))
    }

    private init(vertices: [SIMD3<CSGScalar>], plane: CSGPlane, bounds: AABB) {
        self.vertices = vertices
        self.plane = plane
        self.bounds = bounds
    }

    init?(vertices: [SIMD3<CSGScalar>]) {
        guard vertices.count >= 3 else {
            return nil
        }
        guard let plane = CSGPlane(vertices[0], vertices[1], vertices[2]) else {
            return nil
        }
        self.init(vertices: vertices, plane: plane)
    }

    func flipped() -> Self {
        Self(vertices: vertices.reversed(), plane: plane.flipped(), bounds: bounds)
    }

    var centroid: SIMD3<CSGScalar> {
        vertices.reduce(.zero, +) / CSGScalar(vertices.count)
    }

    func isStrictlyOneSide(of plane: CSGPlane) -> Bool {
        let distances = vertices.map { plane.distanceTo($0) }
        return distances.allSatisfy { $0 > epsilon } || distances.allSatisfy { $0 < -epsilon }
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
    /// Bounding box of all geometry in this subtree (this node + children).
    var bounds = AABB()

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
        node.bounds = bounds
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
            // Early-out: if polygon doesn't overlap this subtree's bounds,
            // classify it by which side of the splitting plane it falls on
            // without recursing deeper or splitting it.
            let polyBounds = polygon.bounds
            if !bounds.isEmpty, !polyBounds.overlaps(bounds) {
                // Determine side by checking any vertex against the splitting plane
                let d = plane.distanceTo(polygon.vertices[0])
                if d >= 0 {
                    frontList.append(polygon)
                } else {
                    backList.append(polygon)
                }
                continue
            }
            splitPolygon(polygon, plane: plane, front: &frontList, back: &backList, coplanarFront: &coplanarFrontList, coplanarBack: &coplanarBackList)
        }

        frontList.append(contentsOf: coplanarFrontList)
        backList.append(contentsOf: coplanarBackList)

        frontList = front?.clipPolygons(frontList) ?? frontList
        backList = back?.clipPolygons(backList) ?? []

        frontList.append(contentsOf: backList)
        return frontList
    }

    /// Remove all polygons in this tree that are inside the other BSP tree.
    func clipTo(_ other: CSGNode) {
        polygons = polygons.flatMap { polygon -> [CSGPolygon] in
            // A polygon that crosses none of the other surface is wholly inside or outside it, so keep or drop it unsplit.
            if !other.surfaceIntersects(polygon, bounds: polygon.bounds), let inside = other.contains(polygon.centroid) {
                return inside ? [] : [polygon]
            }
            return other.clipPolygons([polygon])
        }
        front?.clipTo(other)
        back?.clipTo(other)
    }

    /// Whether `point` is inside the solid, or nil if it lies on a splitting plane.
    func contains(_ point: SIMD3<CSGScalar>) -> Bool? {
        guard let plane else {
            return false
        }
        let distance = plane.distanceTo(point)
        if distance > epsilon {
            guard let front else {
                return false
            }
            return front.contains(point)
        }
        if distance < -epsilon {
            guard let back else {
                return true
            }
            return back.contains(point)
        }
        return nil
    }

    /// Conservatively test whether `polygon` touches any polygon in this subtree. Coplanar contact counts as touching.
    func surfaceIntersects(_ polygon: CSGPolygon, bounds polygonBounds: AABB) -> Bool {
        guard !bounds.isEmpty, polygonBounds.overlaps(bounds.expanded(by: epsilon)) else {
            return false
        }
        for other in polygons where polygonBounds.overlaps(other.bounds.expanded(by: epsilon)) {
            if !polygon.isStrictlyOneSide(of: other.plane), !other.isStrictlyOneSide(of: polygon.plane) {
                return true
            }
        }
        return front?.surfaceIntersects(polygon, bounds: polygonBounds) == true
            || back?.surfaceIntersects(polygon, bounds: polygonBounds) == true
    }

    /// Return all polygons in this BSP tree.
    func allPolygons() -> [CSGPolygon] {
        var result: [CSGPolygon] = []
        collectPolygons(into: &result)
        return result
    }

    private func collectPolygons(into result: inout [CSGPolygon]) {
        result.append(contentsOf: polygons)
        front?.collectPolygons(into: &result)
        back?.collectPolygons(into: &result)
    }

    /// Build a BSP tree from a list of polygons. Called on a fresh or existing node.
    func build(_ list: [CSGPolygon]) {
        guard !list.isEmpty else {
            return
        }

        // Expand bounds to cover all incoming polygon vertices.
        for polygon in list {
            bounds.expandToInclude(polygon.bounds)
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

private let epsilon: CSGScalar = 1e-5

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
    func classify(_ vertex: SIMD3<CSGScalar>) -> PointClassification {
        let t = plane.distanceTo(vertex)
        if t < -epsilon {
            return .back
        }
        if t > epsilon {
            return .front
        }
        return .coplanar
    }

    var polygonType: Int = 0
    for vertex in polygon.vertices {
        polygonType |= classify(vertex).rawValue
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
        let types = polygon.vertices.map(classify)
        var frontVerts: [SIMD3<CSGScalar>] = []
        var backVerts: [SIMD3<CSGScalar>] = []
        frontVerts.reserveCapacity(polygon.vertices.count + 2)
        backVerts.reserveCapacity(polygon.vertices.count + 2)

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
        // The BSP tree algorithm (build/clipTo/invert/allPolygons) is deeply
        // recursive; tree depth scales with mesh complexity and can exceed the
        // default thread stack (notably the small stacks used by swift-testing
        // and Swift concurrency tasks). Run on a dedicated thread with a large
        // stack to avoid stack-overflow crashes.
        nonisolated(unsafe) var result: TriangleSoup?
        let done = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            result = csgImpl(operation, other)
            done.signal()
        }
        thread.stackSize = 64 * 1_024 * 1_024 // 64 MB
        // The caller blocks on this thread, so match its QoS to avoid a priority inversion.
        thread.qualityOfService = Thread.current.qualityOfService
        thread.start()
        done.wait()
        return result ?? Self()
    }

    private func csgImpl(_ operation: CSGOperation, _ other: TriangleSoup) -> TriangleSoup {
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

        return Self.fromPolygons(resultPolygons)
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
            let a = SIMD3<CSGScalar>(positions[tri.0])
            let b = SIMD3<CSGScalar>(positions[tri.1])
            let c = SIMD3<CSGScalar>(positions[tri.2])
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
            soup.positions.append(contentsOf: polygon.vertices.map { SIMD3<Float>($0) })
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
    /// - Parameters:
    ///   - other: The mesh to union with.
    ///   - mergeCoplanar: Merge adjacent coplanar triangles of the result back into n-gons.
    ///   - weldTolerance: Maximum distance for merging result vertices.
    /// - Returns: A new mesh representing the combined volume.
    func union(_ other: Mesh, mergeCoplanar: Bool = true, weldTolerance: Float = 1e-2) -> Mesh {
        csg(.union, other, options: CSGOptions(weldTolerance: weldTolerance, mergeCoplanar: mergeCoplanar))
    }

    /// Returns the CSG intersection of this mesh with another (A ∩ B).
    ///
    /// Both meshes are triangulated, combined via a BSP-tree algorithm, and
    /// the result is rebuilt into a new mesh. Per-corner attributes (normals,
    /// UVs, tangents, colors) are not preserved, and all submeshes are merged
    /// into one.
    ///
    /// - Parameters:
    ///   - other: The mesh to intersect with.
    ///   - mergeCoplanar: Merge adjacent coplanar triangles of the result back into n-gons.
    ///   - weldTolerance: Maximum distance for merging result vertices.
    /// - Returns: A new mesh containing only the shared volume.
    func intersection(_ other: Mesh, mergeCoplanar: Bool = true, weldTolerance: Float = 1e-2) -> Mesh {
        csg(.intersection, other, options: CSGOptions(weldTolerance: weldTolerance, mergeCoplanar: mergeCoplanar))
    }

    /// Returns the CSG difference of this mesh minus another (A − B).
    ///
    /// Both meshes are triangulated, combined via a BSP-tree algorithm, and
    /// the result is rebuilt into a new mesh. Per-corner attributes (normals,
    /// UVs, tangents, colors) are not preserved, and all submeshes are merged
    /// into one.
    ///
    /// - Parameters:
    ///   - other: The mesh volume to subtract.
    ///   - mergeCoplanar: Merge adjacent coplanar triangles of the result back into n-gons.
    ///   - weldTolerance: Maximum distance for merging result vertices.
    /// - Returns: A new mesh with the other's volume carved out.
    func difference(_ other: Mesh, mergeCoplanar: Bool = true, weldTolerance: Float = 1e-2) -> Mesh {
        csg(.difference, other, options: CSGOptions(weldTolerance: weldTolerance, mergeCoplanar: mergeCoplanar))
    }

    /// Perform a CSG operation with explicit options.
    ///
    /// Pipeline: triangulate both meshes into soups (the BSP needs convex polygons),
    /// run the BSP operation, weld the result into a mesh, optionally merge coplanar
    /// faces, then derive `options.attributes`. Input per-corner attributes and
    /// submeshes are not carried through.
    func csg(_ operation: CSGOperation, _ other: Mesh, options: CSGOptions = .init()) -> Mesh {
        var result = TriangleSoup(mesh: self).csg(operation, TriangleSoup(mesh: other)).toMesh(weldTolerance: options.weldTolerance)
        if options.mergeCoplanar {
            result = result.mergingCoplanarFaces(angleTolerance: options.coplanarAngleTolerance, distanceTolerance: options.coplanarDistanceTolerance)
        }
        result.applyAttributes(options.attributes)
        return result
    }
}

/// Tolerances and post-processing for mesh CSG, gathered in one place.
///
/// The BSP split epsilon (1e-5, in Double) is internal and not configurable.
public struct CSGOptions: Sendable {
    /// Maximum distance for merging result vertices.
    public var weldTolerance: Float
    /// Merge adjacent coplanar triangles back into n-gons.
    public var mergeCoplanar: Bool
    /// Maximum angle (radians) between normals for faces to count as coplanar.
    public var coplanarAngleTolerance: Float
    /// Maximum distance between planes for faces to count as coplanar.
    public var coplanarDistanceTolerance: Float
    /// Attributes to derive on the result (for example `.flatNormals`). Input attributes are not preserved.
    public var attributes: MeshAttributes

    /// Creates options. The defaults match `union`/`intersection`/`difference` without arguments.
    public init(weldTolerance: Float = 1e-2, mergeCoplanar: Bool = true, coplanarAngleTolerance: Float = 1e-4, coplanarDistanceTolerance: Float = 1e-4, attributes: MeshAttributes = []) {
        self.weldTolerance = weldTolerance
        self.mergeCoplanar = mergeCoplanar
        self.coplanarAngleTolerance = coplanarAngleTolerance
        self.coplanarDistanceTolerance = coplanarDistanceTolerance
        self.attributes = attributes
    }
}
