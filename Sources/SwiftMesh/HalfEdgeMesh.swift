import CoreGraphics
import Foundation

// MARK: - Inlined support types (originally from GeometryLite2D/Geometry)

/// A value paired with a stable identifier.
public struct Identified<ID, Value>: Identifiable where ID: Hashable {
    public var id: ID
    public var value: Value

    public init(id: ID, value: Value) {
        self.id = id
        self.value = value
    }
}

extension Identified: Sendable where ID: Sendable, Value: Sendable {}
extension Identified: Equatable where ID: Equatable, Value: Equatable {}
extension Identified: Hashable where ID: Hashable, Value: Hashable {}

/// A type-erased composite key for hashing pairs of values.
struct Composite<each T> {
    private let children: (repeat each T)

    init(_ children: repeat each T) {
        self.children = (repeat each children)
    }
}

extension Composite: Equatable where repeat each T: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        for (left, right) in repeat (each lhs.children, each rhs.children) {
            guard left == right else { return false }
        }
        return true
    }
}

extension Composite: Hashable where repeat each T: Hashable {
    func hash(into hasher: inout Hasher) {
        for child in repeat (each children) {
            child.hash(into: &hasher)
        }
    }
}

extension Composite: Sendable where repeat each T: Sendable {}

/// A directed line segment in 2D.
public struct LineSegment: Hashable, Sendable {
    public var start: CGPoint
    public var end: CGPoint

    public init(start: CGPoint, end: CGPoint) {
        self.start = start
        self.end = end
    }
}

// MARK: - Private helpers

private extension CGPoint {
    func angle(to other: CGPoint) -> CGFloat {
        atan2(other.y - y, other.x - x)
    }
}

/// Shoelace formula for signed area of a simple polygon.
private func signedArea(of points: [CGPoint]) -> CGFloat {
    guard points.count >= 3 else { return 0 }
    var sum: CGFloat = 0
    for i in 0..<points.count {
        let current = points[i]
        let next = points[(i + 1) % points.count]
        sum += (current.x * next.y) - (next.x * current.y)
    }
    return sum / 2
}

// MARK: - HalfEdgeMesh

public struct HalfEdgeMesh<ID: Hashable> {
    // Stable ids
    public struct VertexID: Hashable, Sendable { public let raw: Int; public init(raw: Int) { self.raw = raw } }
    public struct HalfEdgeID: Hashable, Sendable { public let raw: Int; public init(raw: Int) { self.raw = raw } }
    public struct FaceID: Hashable, Sendable { public let raw: Int; public init(raw: Int) { self.raw = raw } }

    public struct Vertex {
        public let id: VertexID
        public var p: CGPoint
        public var edge: HalfEdgeID? // one outgoing
    }

    public struct HalfEdge {
        public let id: HalfEdgeID
        public let origin: VertexID
        public var twin: HalfEdgeID?
        public var next: HalfEdgeID?
        public var prev: HalfEdgeID?
        public var face: FaceID?
        public let segmentID: ID
        // cached angle at origin (radians, [-π, π])
        fileprivate var angle: CGFloat
    }

    public struct Face {
        public let id: FaceID
        public var edge: HalfEdgeID? // outer boundary edge
        public var holeEdges: [HalfEdgeID] = [] // one half-edge per hole loop
        public var signedArea: CGFloat? // computed after labeling (outer boundary only)
    }

    public var vertices: [Vertex] = []
    public private(set) var halfEdges: [HalfEdge] = []
    public private(set) var faces: [Face] = []

    // Build from clean segments (deduped, split at T's)
    public init(segments: [Identified<ID, LineSegment>]) {
        build(from: segments)
    }

    /// A face definition for building a mesh from indexed points.
    public struct FaceDefinition {
        public var outer: [Int]
        public var holes: [[Int]]

        public init(outer: [Int], holes: [[Int]] = []) {
            self.outer = outer
            self.holes = holes
        }
    }

    /// Build from indexed points and face definitions (with optional holes).
    ///
    /// Vertex indices are preserved (mesh vertex N = points[N]).
    /// The `ID` for each half-edge is the undirected edge index (sequential, shared by twin pairs).
    public init(points: [CGPoint], faces faceDefinitions: [FaceDefinition]) where ID == Int {
        // 1. Create vertices, preserving index order
        vertices = points.enumerated().map { i, p in
            Vertex(id: VertexID(raw: i), p: p, edge: nil)
        }

        // Map (origin, dest) -> halfEdgeID for twin linking
        // Encode directed edge as origin * points.count + dest
        let n = points.count
        var edgeMap: [Int: HalfEdgeID] = [:]
        var undirectedEdgeCount = 0

        // Helper: create half-edges for a loop, assign them to fID, return first HE index
        func buildLoop(_ loop: [Int], faceID fID: FaceID) -> HalfEdgeID? {
            guard loop.count >= 3 else {
                return nil
            }
            let firstHEIdx = halfEdges.count

            for i in 0..<loop.count {
                let originIdx = loop[i]
                let destIdx = loop[(i + 1) % loop.count]
                let heID = HalfEdgeID(raw: halfEdges.count)
                let ang = points[originIdx].angle(to: points[destIdx])

                let forwardKey = originIdx * n + destIdx
                let reverseKey = destIdx * n + originIdx

                let segID: Int
                var twin: HalfEdgeID? = nil
                if let twinID = edgeMap[reverseKey] {
                    segID = halfEdges[twinID.raw].segmentID
                    twin = twinID
                    halfEdges[twinID.raw].twin = heID
                } else {
                    segID = undirectedEdgeCount
                    undirectedEdgeCount += 1
                }

                halfEdges.append(HalfEdge(
                    id: heID,
                    origin: VertexID(raw: originIdx),
                    twin: twin,
                    next: nil,
                    prev: nil,
                    face: fID,
                    segmentID: segID,
                    angle: ang
                ))

                edgeMap[forwardKey] = heID

                if vertices[originIdx].edge == nil {
                    vertices[originIdx].edge = heID
                }
            }

            // Link next/prev within the loop
            for i in 0..<loop.count {
                let heIdx = firstHEIdx + i
                let nextIdx = firstHEIdx + (i + 1) % loop.count
                let prevIdx = firstHEIdx + (i + loop.count - 1) % loop.count
                halfEdges[heIdx].next = HalfEdgeID(raw: nextIdx)
                halfEdges[heIdx].prev = HalfEdgeID(raw: prevIdx)
            }

            return HalfEdgeID(raw: firstHEIdx)
        }

        for def in faceDefinitions {
            let fID = FaceID(raw: faces.count)

            guard let outerEdge = buildLoop(def.outer, faceID: fID) else {
                continue
            }

            let holeEdges = def.holes.compactMap { buildLoop($0, faceID: fID) }

            let outerPts = def.outer.map { points[$0] }
            let area = signedArea(of: outerPts)
            faces.append(Face(id: fID, edge: outerEdge, holeEdges: holeEdges, signedArea: area))
        }
    }

    // MARK: - Accessors

    @inlinable public func point(_ v: VertexID) -> CGPoint { vertices[v.raw].p }

    @inlinable public func dest(of e: HalfEdgeID) -> VertexID? {
        guard let t = halfEdges[e.raw].twin else { return nil }
        return halfEdges[t.raw].origin
    }

    // MARK: - Build steps

    private mutating func build(from segments: [Identified<ID, LineSegment>]) {
        // 1) Make vertices (exact point hashing is fine given "clean" data)
        var vIndex: [CGPoint: VertexID] = [:]
        func vID(for p: CGPoint) -> VertexID {
            if let id = vIndex[p] { return id }
            let id = VertexID(raw: vertices.count)
            vertices.append(Vertex(id: id, p: p, edge: nil))
            vIndex[p] = id
            return id
        }

        // 2) Create 2 half-edges per segment (both directions) and link twins
        var pendingTwins: [Composite<VertexID, VertexID>: HalfEdgeID] = [:]
        halfEdges.reserveCapacity(segments.count * 2)

        for s in segments {
            let a = vID(for: s.value.start)
            let b = vID(for: s.value.end)
            // dir a->b
            let e0 = HalfEdgeID(raw: halfEdges.count)
            let ang0 = vertices[a.raw].p.angle(to: vertices[b.raw].p)
            halfEdges.append(HalfEdge(id: e0, origin: a, twin: nil, next: nil, prev: nil, face: nil, segmentID: s.id, angle: ang0))
            // dir b->a
            let e1 = HalfEdgeID(raw: halfEdges.count)
            let ang1 = vertices[b.raw].p.angle(to: vertices[a.raw].p)
            halfEdges.append(HalfEdge(id: e1, origin: b, twin: nil, next: nil, prev: nil, face: nil, segmentID: s.id, angle: ang1))

            // set twins
            halfEdges[e0.raw].twin = e1
            halfEdges[e1.raw].twin = e0

            // seed vertex.outgoing if empty
            if vertices[a.raw].edge == nil { vertices[a.raw].edge = e0 }
            if vertices[b.raw].edge == nil { vertices[b.raw].edge = e1 }

            // record for wiring later
            pendingTwins[.init(a, b)] = e0
            pendingTwins[.init(b, a)] = e1
        }

        // 3) For each vertex, sort outgoing edges by angle CCW
        var outgoing: [[HalfEdgeID]] = Array(repeating: [], count: vertices.count)
        for he in halfEdges {
            outgoing[he.origin.raw].append(he.id)
        }
        for i in 0..<outgoing.count {
            outgoing[i].sort { halfEdges[$0.raw].angle < halfEdges[$1.raw].angle }
            if let first = outgoing[i].first { vertices[i].edge = first }
        }

        // 4) Wire next/prev
        for e in halfEdges.indices {
            guard let twin = halfEdges[e].twin,
                  let v = dest(of: halfEdges[e].id) else { continue }
            let list = outgoing[v.raw]
            if let idx = list.firstIndex(of: twin) {
                let nextIdx = (idx + 1) % list.count
                let ne = list[nextIdx]
                if ne == twin { continue }
                halfEdges[e].next = ne
                halfEdges[ne.raw].prev = halfEdges[e].id
            }
        }

        // 5) Face labeling: traverse unvisited cycles via next pointers
        var faceForEdge: [Bool] = Array(repeating: false, count: halfEdges.count)
        var builtFaces: [Face] = []

        for eIdx in halfEdges.indices {
            if faceForEdge[eIdx] { continue }
            var loop: [HalfEdgeID] = []
            var e = halfEdges[eIdx].id
            var ok = true
            var seen = Set<HalfEdgeID>()
            while !seen.contains(e) {
                seen.insert(e)
                loop.append(e)
                guard let n = halfEdges[e.raw].next else { ok = false; break }
                e = n
            }
            guard ok, e == loop.first! else { continue }

            let fID = FaceID(raw: builtFaces.count)
            for heID in loop {
                halfEdges[heID.raw].face = fID
                faceForEdge[heID.raw] = true
            }
            var f = Face(id: fID, edge: loop.first, signedArea: nil)

            var pts: [CGPoint] = []
            pts.reserveCapacity(loop.count)
            for heID in loop {
                let o = halfEdges[heID.raw].origin
                pts.append(vertices[o.raw].p)
            }
            f.signedArea = signedArea(of: pts)
            builtFaces.append(f)
        }

        self.faces = builtFaces
    }
}

// MARK: - Convenience

extension HalfEdgeMesh.HalfEdgeID: CustomStringConvertible {
    public var description: String { "H\(raw)" }
}
extension HalfEdgeMesh.VertexID: CustomStringConvertible {
    public var description: String { "V\(raw)" }
}
extension HalfEdgeMesh.FaceID: CustomStringConvertible {
    public var description: String { "F\(raw)" }
}

// MARK: - Validation & Queries

extension HalfEdgeMesh {

    /// Validates the consistency of the half-edge mesh structure.
    /// Returns nil if valid, or an error message describing the first issue found.
    public func validate() -> String? {
        // Check 1: All vertices should be referenced by at least one half-edge
        var verticesInEdges = Set<VertexID>()
        for edge in halfEdges {
            verticesInEdges.insert(edge.origin)
        }

        for vertex in vertices {
            if !verticesInEdges.contains(vertex.id) {
                return "Vertex \(vertex.id) at \(vertex.p) is not referenced by any half-edge"
            }
            if let edgeID = vertex.edge {
                if edgeID.raw >= halfEdges.count {
                    return "Vertex \(vertex.id) has invalid edge reference \(edgeID)"
                }
                if halfEdges[edgeID.raw].origin != vertex.id {
                    return "Vertex \(vertex.id) references edge \(edgeID) which doesn't originate from it"
                }
            }
        }

        // Check 2: Each half-edge should be in at least one face (unless boundary)
        for edge in halfEdges {
            if edge.face == nil {
                if edge.twin == nil {
                    return "Edge \(edge.id) has no face and no twin"
                }
            }
        }

        // Check 3: Twin relationships are symmetric
        for edge in halfEdges {
            if let twinID = edge.twin {
                if twinID.raw >= halfEdges.count {
                    return "Edge \(edge.id) has invalid twin reference \(twinID)"
                }
                let twin = halfEdges[twinID.raw]
                if twin.twin != edge.id {
                    return "Edge \(edge.id) has twin \(twinID), but that edge's twin is \(twin.twin?.description ?? "nil")"
                }
                if let twinDest = dest(of: edge.id), twin.origin != twinDest {
                    return "Edge \(edge.id) and its twin \(twinID) don't have opposite vertices"
                }
                if let edgeDest = dest(of: twinID), edge.origin != edgeDest {
                    return "Edge \(edge.id) and its twin \(twinID) don't have opposite vertices"
                }
            }
        }

        // Check 4: Next/prev relationships are consistent
        for edge in halfEdges {
            if let nextID = edge.next {
                if nextID.raw >= halfEdges.count {
                    return "Edge \(edge.id) has invalid next reference \(nextID)"
                }
                let next = halfEdges[nextID.raw]
                if next.prev != edge.id {
                    return "Edge \(edge.id) has next \(nextID), but that edge's prev is \(next.prev?.description ?? "nil")"
                }
            }
            if let prevID = edge.prev {
                if prevID.raw >= halfEdges.count {
                    return "Edge \(edge.id) has invalid prev reference \(prevID)"
                }
                let prev = halfEdges[prevID.raw]
                if prev.next != edge.id {
                    return "Edge \(edge.id) has prev \(prevID), but that edge's next is \(prev.next?.description ?? "nil")"
                }
            }
        }

        // Check 5: Face boundaries form closed loops
        for face in faces {
            guard let startEdge = face.edge else {
                return "Face \(face.id) has no boundary edge"
            }
            if startEdge.raw >= halfEdges.count {
                return "Face \(face.id) has invalid edge reference \(startEdge)"
            }
            var visited = Set<HalfEdgeID>()
            var currentEdge = startEdge
            var loopCount = 0
            let maxLoopCount = halfEdges.count + 1

            while loopCount < maxLoopCount {
                if visited.contains(currentEdge) {
                    if currentEdge != startEdge {
                        return "Face \(face.id) boundary doesn't form a proper closed loop (revisited \(currentEdge) before returning to start)"
                    }
                    break
                }
                visited.insert(currentEdge)
                let edge = halfEdges[currentEdge.raw]
                if edge.face != face.id {
                    return "Face \(face.id) references edge \(currentEdge) which belongs to face \(edge.face?.description ?? "nil")"
                }
                guard let nextEdge = edge.next else {
                    return "Face \(face.id) has edge \(currentEdge) with no next pointer (open boundary)"
                }
                currentEdge = nextEdge
                loopCount += 1
            }
            if loopCount >= maxLoopCount {
                return "Face \(face.id) boundary appears to be infinite or malformed"
            }
            if visited.count < 3 {
                return "Face \(face.id) has degenerate boundary with only \(visited.count) edges"
            }
        }

        // Check 6: No edge should reference non-existent faces
        for edge in halfEdges {
            if let faceID = edge.face {
                if faceID.raw >= faces.count {
                    return "Edge \(edge.id) references non-existent face \(faceID)"
                }
            }
        }

        return nil
    }

    // MARK: - Face queries

    /// Whether this face has clockwise winding (negative signed area), indicating a hole.
    public func isHole(_ face: FaceID) -> Bool {
        guard let area = faces[face.raw].signedArea else { return false }
        return area < 0
    }

    /// Return the outer boundary of `face` as points.
    public func polygon(for face: FaceID) -> [CGPoint] {
        guard let start = faces[face.raw].edge else { return [] }
        return collectLoop(startEdge: start)
    }

    /// Return the hole boundaries of `face` as arrays of points.
    public func holePolygons(for face: FaceID) -> [[CGPoint]] {
        faces[face.raw].holeEdges.map { collectLoop(startEdge: $0) }
    }

    /// Return the ordered boundary of `face` as vertex IDs.
    public func vertexLoop(for face: FaceID) -> [VertexID] {
        guard let start = faces[face.raw].edge else { return [] }
        var ids: [VertexID] = []
        var e = start
        var visited = Set<HalfEdgeID>()
        while !visited.contains(e) {
            visited.insert(e)
            ids.append(halfEdges[e.raw].origin)
            guard let n = halfEdges[e.raw].next else { break }
            e = n
        }
        if e != start || ids.count < 3 { return [] }
        return ids
    }

    /// Returns faces that share an edge with the given face.
    public func neighborFaces(of face: FaceID) -> [FaceID] {
        var neighbors = Set<FaceID>()
        guard let startEdge = faces[face.raw].edge else { return [] }

        func walkLoop(from start: HalfEdgeID) {
            var e = start
            var visited = Set<HalfEdgeID>()
            while !visited.contains(e) {
                visited.insert(e)
                if let twinID = halfEdges[e.raw].twin, let twinFace = halfEdges[twinID.raw].face, twinFace != face {
                    neighbors.insert(twinFace)
                }
                guard let n = halfEdges[e.raw].next else { break }
                e = n
            }
        }

        walkLoop(from: startEdge)
        for holeEdge in faces[face.raw].holeEdges {
            walkLoop(from: holeEdge)
        }
        return Array(neighbors)
    }

    /// Whether the face is convex (all interior angles < 180°).
    public func isConvex(_ face: FaceID) -> Bool {
        let pts = polygon(for: face)
        guard pts.count >= 3 else { return false }
        let n = pts.count
        var sign: Bool?
        for i in 0..<n {
            let a = pts[i]
            let b = pts[(i + 1) % n]
            let c = pts[(i + 2) % n]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if cross != 0 {
                let positive = cross > 0
                if let s = sign {
                    if s != positive { return false }
                } else {
                    sign = positive
                }
            }
        }
        return true
    }

    /// Returns closed loops formed by boundary half-edges (those with no twin).
    public func boundaryLoops() -> [[CGPoint]] {
        var visited = Set<HalfEdgeID>()
        var loops: [[CGPoint]] = []

        for he in halfEdges where he.twin == nil {
            if visited.contains(he.id) { continue }
            var loop: [CGPoint] = []
            var current = he.id
            while !visited.contains(current) {
                visited.insert(current)
                let edge = halfEdges[current.raw]
                loop.append(vertices[edge.origin.raw].p)
                guard let next = edge.next else { break }
                var walker = next
                var safety = halfEdges.count
                while halfEdges[walker.raw].twin != nil, safety > 0 {
                    guard let twinNext = halfEdges[halfEdges[walker.raw].twin!.raw].next else { break }
                    walker = twinNext
                    safety -= 1
                }
                if safety == 0 { break }
                current = walker
            }
            if loop.count >= 3 {
                loops.append(loop)
            }
        }
        return loops
    }

    /// Returns all unique undirected edges as (vertexA, vertexB, segmentID) triples.
    public func undirectedEdges() -> [(VertexID, VertexID, ID)] {
        var seen = Set<ID>()
        var result: [(VertexID, VertexID, ID)] = []
        for he in halfEdges {
            if !seen.contains(he.segmentID) {
                seen.insert(he.segmentID)
                let origin = he.origin
                if let twinID = he.twin {
                    result.append((origin, halfEdges[twinID.raw].origin, he.segmentID))
                } else if let nextID = he.next {
                    result.append((origin, halfEdges[nextID.raw].origin, he.segmentID))
                }
            }
        }
        return result
    }

    // MARK: - Edge deletion

    /// Delete an undirected edge by its segment ID.
    /// If the edge is interior (shared by two faces), the two faces are merged into one.
    /// If the edge is boundary (one face), it is removed from that face.
    public mutating func deleteEdge(segmentID: ID) where ID: Equatable {
        var heIndices: [Int] = []
        for i in halfEdges.indices where halfEdges[i].segmentID == segmentID {
            heIndices.append(i)
        }
        guard !heIndices.isEmpty else { return }

        let heA = heIndices[0]
        let heB = heIndices.count > 1 ? heIndices[1] : nil

        let prevA = halfEdges[heA].prev
        let nextA = halfEdges[heA].next
        let faceA = halfEdges[heA].face

        if let p = prevA, let n = nextA {
            halfEdges[p.raw].next = n
            halfEdges[n.raw].prev = p
        }

        if let heB {
            let prevB = halfEdges[heB].prev
            let nextB = halfEdges[heB].next
            let faceB = halfEdges[heB].face

            if let p = prevB, let n = nextB {
                halfEdges[p.raw].next = n
                halfEdges[n.raw].prev = p
            }

            if let fA = faceA, let fB = faceB, fA != fB {
                if let startB = nextB {
                    var e = startB
                    var visited = Set<HalfEdgeID>()
                    while !visited.contains(e) {
                        visited.insert(e)
                        halfEdges[e.raw].face = fA
                        guard let n = halfEdges[e.raw].next else { break }
                        e = n
                        if e == startB { break }
                    }
                }

                if let pA = prevA, let nB = nextB {
                    halfEdges[pA.raw].next = nB
                    halfEdges[nB.raw].prev = pA
                }
                if let pB = prevB, let nA = nextA {
                    halfEdges[pB.raw].next = nA
                    halfEdges[nA.raw].prev = pB
                }

                if let nA = nextA {
                    faces[fA.raw].edge = nA
                }

                faces[fB.raw].edge = nil

                let pts = polygon(for: fA)
                faces[fA.raw].signedArea = pts.count >= 3 ? signedArea(of: pts) : nil
            } else if let fA = faceA {
                if let n = nextA {
                    faces[fA.raw].edge = n
                }
            }

            halfEdges[heB].twin = nil
            halfEdges[heB].next = nil
            halfEdges[heB].prev = nil
            halfEdges[heB].face = nil
        } else {
            if let fA = faceA, let n = nextA {
                faces[fA.raw].edge = n
            }
        }

        halfEdges[heA].twin = nil
        halfEdges[heA].next = nil
        halfEdges[heA].prev = nil
        halfEdges[heA].face = nil

        let originA = halfEdges[heA].origin
        if vertices[originA.raw].edge?.raw == heA {
            vertices[originA.raw].edge = halfEdges.first(where: { $0.origin == originA && $0.next != nil })?.id
        }
        if let heB {
            let originB = halfEdges[heB].origin
            if vertices[originB.raw].edge?.raw == heB {
                vertices[originB.raw].edge = halfEdges.first(where: { $0.origin == originB && $0.next != nil })?.id
            }
        }
    }

    // MARK: - Internals

    private func collectLoop(startEdge: HalfEdgeID) -> [CGPoint] {
        var pts: [CGPoint] = []
        var e = startEdge
        var visited = Set<HalfEdgeID>()
        while !visited.contains(e) {
            visited.insert(e)
            let he = halfEdges[e.raw]
            pts.append(vertices[he.origin.raw].p)
            guard let n = he.next else { break }
            e = n
        }
        if e != startEdge || pts.count < 3 { return [] }
        return pts
    }
}
