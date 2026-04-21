import CoreGraphics
import Foundation
import Geometry

// MARK: - Mesh2D

/// A 2D mesh: half-edge topology paired with per-vertex `CGPoint` positions
/// and optional per-half-edge segment labels.
///
/// Provides planar-subdivision construction from arbitrary (deduped, presplit)
/// line segments, plus 2D-specific queries (polygon extraction, signed area, convexity,
/// boundary loops, edge deletion).
public struct Mesh2D<ID: Hashable & Sendable>: Sendable {
    /// The combinatorial topology (vertices, half-edges, faces, wiring).
    public var topology: HalfEdgeTopology

    /// Per-vertex positions. Count equals `topology.vertices.count`, indexed by `VertexID.raw`.
    public var positions: [CGPoint]

    /// Per-half-edge segment labels. Count equals `topology.halfEdges.count`, indexed by `HalfEdgeID.raw`.
    ///
    /// Twin pairs of half-edges share the same label (they correspond to the same undirected edge).
    public var edgeLabels: [ID]

    /// Per-face signed area of the outer boundary, if computed. Indexed by `FaceID.raw`.
    public var faceSignedAreas: [CGFloat?]

    public init(topology: HalfEdgeTopology, positions: [CGPoint], edgeLabels: [ID], faceSignedAreas: [CGFloat?]) {
        self.topology = topology
        self.positions = positions
        self.edgeLabels = edgeLabels
        self.faceSignedAreas = faceSignedAreas
    }

    // MARK: - Type aliases

    public typealias VertexID = HalfEdgeTopology.VertexID
    public typealias HalfEdgeID = HalfEdgeTopology.HalfEdgeID
    public typealias FaceID = HalfEdgeTopology.FaceID

    // MARK: - Accessors

    @inlinable public func point(_ v: VertexID) -> CGPoint { positions[v.raw] }

    @inlinable public func label(_ e: HalfEdgeID) -> ID { edgeLabels[e.raw] }

    @inlinable public func dest(of e: HalfEdgeID) -> VertexID? {
        guard let t = topology.halfEdges[e.raw].twin else { return nil }
        return topology.halfEdges[t.raw].origin
    }
}

// MARK: - Construction from segments (planar subdivision)

extension Mesh2D {
    /// Build a 2D mesh from clean (deduped, split-at-T-junctions) line segments.
    ///
    /// Each segment becomes a pair of twin half-edges. Edges sharing an endpoint are
    /// sorted CCW by angle at that vertex, then next/prev are wired so each closed cycle
    /// forms a face (with signed area). Boundary loops (open chains) remain unassigned.
    public init(segments: [Identified<ID, LineSegment>]) {
        var topology = HalfEdgeTopology()
        var positions: [CGPoint] = []
        var edgeLabels: [ID] = []

        // Per-half-edge cached angle at origin (radians, [-π, π]).
        var angles: [CGFloat] = []

        // 1) Make vertices (exact point hashing is fine given "clean" data).
        var vIndex: [CGPoint: VertexID] = [:]
        func vID(for p: CGPoint) -> VertexID {
            if let id = vIndex[p] { return id }
            let id = VertexID(raw: positions.count)
            positions.append(p)
            topology.vertices.append(HalfEdgeTopology.Vertex(id: id, edge: nil))
            vIndex[p] = id
            return id
        }

        // 2) Create two half-edges per segment and link twins.
        topology.halfEdges.reserveCapacity(segments.count * 2)
        edgeLabels.reserveCapacity(segments.count * 2)
        angles.reserveCapacity(segments.count * 2)

        for s in segments {
            let a = vID(for: s.value.start)
            let b = vID(for: s.value.end)

            let e0 = HalfEdgeID(raw: topology.halfEdges.count)
            let ang0 = positions[a.raw].angle(to: positions[b.raw])
            topology.halfEdges.append(HalfEdgeTopology.HalfEdge(id: e0, origin: a, twin: nil, next: nil, prev: nil, face: nil))
            edgeLabels.append(s.id)
            angles.append(ang0)

            let e1 = HalfEdgeID(raw: topology.halfEdges.count)
            let ang1 = positions[b.raw].angle(to: positions[a.raw])
            topology.halfEdges.append(HalfEdgeTopology.HalfEdge(id: e1, origin: b, twin: nil, next: nil, prev: nil, face: nil))
            edgeLabels.append(s.id)
            angles.append(ang1)

            topology.halfEdges[e0.raw].twin = e1
            topology.halfEdges[e1.raw].twin = e0

            if topology.vertices[a.raw].edge == nil { topology.vertices[a.raw].edge = e0 }
            if topology.vertices[b.raw].edge == nil { topology.vertices[b.raw].edge = e1 }
        }

        // 3) For each vertex, sort outgoing edges CCW by cached angle.
        var outgoing: [[HalfEdgeID]] = Array(repeating: [], count: topology.vertices.count)
        for he in topology.halfEdges {
            outgoing[he.origin.raw].append(he.id)
        }
        for i in 0..<outgoing.count {
            outgoing[i].sort { angles[$0.raw] < angles[$1.raw] }
            if let first = outgoing[i].first {
                topology.vertices[i].edge = first
            }
        }

        // 4) Wire next/prev so the face-on-left invariant holds.
        //    For half-edge e with twin t ending at v: next(e) is the outgoing edge
        //    immediately after t in CCW order at v.
        for e in topology.halfEdges.indices {
            guard let twin = topology.halfEdges[e].twin else { continue }
            let twinOrigin = topology.halfEdges[twin.raw].origin
            let list = outgoing[twinOrigin.raw]
            guard let idx = list.firstIndex(of: twin) else { continue }
            let nextIdx = (idx + 1) % list.count
            let ne = list[nextIdx]
            // Skip degenerate successor (would create a 2-edge cycle).
            if ne == twin { continue }
            topology.halfEdges[e].next = ne
            topology.halfEdges[ne.raw].prev = topology.halfEdges[e].id
        }

        // 5) Face labeling: traverse unvisited closed cycles via next pointers.
        var faceForEdge: [Bool] = Array(repeating: false, count: topology.halfEdges.count)
        var faceSignedAreas: [CGFloat?] = []

        for eIdx in topology.halfEdges.indices {
            if faceForEdge[eIdx] { continue }
            var loop: [HalfEdgeID] = []
            var e = topology.halfEdges[eIdx].id
            var seen = Set<HalfEdgeID>()
            var ok = true
            while !seen.contains(e) {
                seen.insert(e)
                loop.append(e)
                guard let n = topology.halfEdges[e.raw].next else { ok = false; break }
                e = n
            }
            guard ok, e == loop.first! else { continue }

            let fID = FaceID(raw: topology.faces.count)
            for heID in loop {
                topology.halfEdges[heID.raw].face = fID
                faceForEdge[heID.raw] = true
            }

            var pts: [CGPoint] = []
            pts.reserveCapacity(loop.count)
            for heID in loop {
                let o = topology.halfEdges[heID.raw].origin
                pts.append(positions[o.raw])
            }
            let area = Polygon(pts).signedArea

            topology.faces.append(HalfEdgeTopology.Face(id: fID, edge: loop.first, holeEdges: []))
            faceSignedAreas.append(area)
        }

        self.init(topology: topology, positions: positions, edgeLabels: edgeLabels, faceSignedAreas: faceSignedAreas)
    }
}

// MARK: - Construction from points + face definitions

extension Mesh2D where ID == Int {
    /// Build a 2D mesh from indexed points and face definitions (with optional holes).
    ///
    /// Vertex indices are preserved (mesh vertex N = points[N]).
    /// The label for each half-edge is the undirected edge index (sequential, shared by twin pairs).
    public init(points: [CGPoint], faces faceDefinitions: [HalfEdgeTopology.FaceDefinition]) {
        var topology = HalfEdgeTopology()
        var edgeLabels: [Int] = []
        var faceSignedAreas: [CGFloat?] = []

        // 1. Create vertices, preserving index order.
        topology.vertices = (0..<points.count).map { HalfEdgeTopology.Vertex(id: VertexID(raw: $0), edge: nil) }

        let n = points.count
        var edgeMap: [Int: HalfEdgeID] = [:] // encoded directed edge -> half-edge
        var undirectedEdgeCount = 0

        func buildLoop(_ loop: [Int], faceID fID: FaceID) -> HalfEdgeID? {
            guard loop.count >= 3 else { return nil }
            let firstHEIdx = topology.halfEdges.count

            for i in 0..<loop.count {
                let originIdx = loop[i]
                let destIdx = loop[(i + 1) % loop.count]
                let heID = HalfEdgeID(raw: topology.halfEdges.count)

                let forwardKey = originIdx * n + destIdx
                let reverseKey = destIdx * n + originIdx

                let segID: Int
                var twin: HalfEdgeID?
                if let twinID = edgeMap[reverseKey] {
                    segID = edgeLabels[twinID.raw]
                    twin = twinID
                    topology.halfEdges[twinID.raw].twin = heID
                } else {
                    segID = undirectedEdgeCount
                    undirectedEdgeCount += 1
                }

                topology.halfEdges.append(HalfEdgeTopology.HalfEdge(id: heID, origin: VertexID(raw: originIdx), twin: twin, next: nil, prev: nil, face: fID))
                edgeLabels.append(segID)

                edgeMap[forwardKey] = heID

                if topology.vertices[originIdx].edge == nil {
                    topology.vertices[originIdx].edge = heID
                }
            }

            // Link next/prev within the loop.
            for i in 0..<loop.count {
                let heIdx = firstHEIdx + i
                let nextIdx = firstHEIdx + (i + 1) % loop.count
                let prevIdx = firstHEIdx + (i + loop.count - 1) % loop.count
                topology.halfEdges[heIdx].next = HalfEdgeID(raw: nextIdx)
                topology.halfEdges[heIdx].prev = HalfEdgeID(raw: prevIdx)
            }

            return HalfEdgeID(raw: firstHEIdx)
        }

        for def in faceDefinitions {
            let fID = FaceID(raw: topology.faces.count)

            guard let outerEdge = buildLoop(def.outer, faceID: fID) else { continue }

            let holeEdges = def.holes.compactMap { buildLoop($0, faceID: fID) }

            let outerPts = def.outer.map { points[$0] }
            let area = Polygon(outerPts).signedArea

            topology.faces.append(HalfEdgeTopology.Face(id: fID, edge: outerEdge, holeEdges: holeEdges))
            faceSignedAreas.append(area)
        }

        self.init(topology: topology, positions: points, edgeLabels: edgeLabels, faceSignedAreas: faceSignedAreas)
    }
}

// MARK: - 2D queries

extension Mesh2D {
    /// Whether this face has clockwise winding (negative signed area), indicating a hole.
    public func isHole(_ face: FaceID) -> Bool {
        guard let area = faceSignedAreas[face.raw] else { return false }
        return area < 0
    }

    /// Signed area of the outer boundary of this face (if computed).
    public func signedArea(_ face: FaceID) -> CGFloat? {
        faceSignedAreas[face.raw]
    }

    /// Outer boundary of `face` as points.
    public func polygon(for face: FaceID) -> [CGPoint] {
        guard let start = topology.faces[face.raw].edge else { return [] }
        return collectLoop(startEdge: start)
    }

    /// Hole boundaries of `face` as arrays of points.
    public func holePolygons(for face: FaceID) -> [[CGPoint]] {
        topology.faces[face.raw].holeEdges.map { collectLoop(startEdge: $0) }
    }

    /// Whether the face is convex (all interior cross-products same sign).
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

    /// Closed loops formed by boundary half-edges (those with no twin).
    /// Each loop is an array of points tracing one connected boundary.
    public func boundaryLoops() -> [[CGPoint]] {
        var visited = Set<HalfEdgeID>()
        var loops: [[CGPoint]] = []

        for he in topology.halfEdges where he.twin == nil {
            if visited.contains(he.id) { continue }
            var loop: [CGPoint] = []
            var current = he.id
            while !visited.contains(current) {
                visited.insert(current)
                let edge = topology.halfEdges[current.raw]
                loop.append(positions[edge.origin.raw])
                guard let next = edge.next else { break }
                // Walk across interior edges until we hit the next boundary edge.
                var walker = next
                var safety = topology.halfEdges.count
                while topology.halfEdges[walker.raw].twin != nil, safety > 0 {
                    guard let twinNext = topology.halfEdges[topology.halfEdges[walker.raw].twin!.raw].next else {
                        break
                    }
                    walker = twinNext
                    safety -= 1
                }
                if safety == 0 { break }
                current = walker
            }
            if loop.count >= 3 { loops.append(loop) }
        }
        return loops
    }

    /// All unique undirected edges as (vertexA, vertexB, label) triples.
    /// Each undirected edge appears exactly once.
    public func undirectedEdges() -> [(VertexID, VertexID, ID)] {
        var seen = Set<Int>()
        var result: [(VertexID, VertexID, ID)] = []
        for he in topology.halfEdges {
            let heIdx = he.id.raw
            let twinIdx = he.twin?.raw ?? heIdx
            let canonical = min(heIdx, twinIdx)
            if seen.contains(canonical) { continue }
            seen.insert(canonical)

            let origin = he.origin
            if let twinID = he.twin {
                result.append((origin, topology.halfEdges[twinID.raw].origin, edgeLabels[heIdx]))
            } else if let nextID = he.next {
                result.append((origin, topology.halfEdges[nextID.raw].origin, edgeLabels[heIdx]))
            }
        }
        return result
    }

    // MARK: - Internals

    private func collectLoop(startEdge: HalfEdgeID) -> [CGPoint] {
        var pts: [CGPoint] = []
        var e = startEdge
        var visited = Set<HalfEdgeID>()
        while !visited.contains(e) {
            visited.insert(e)
            let he = topology.halfEdges[e.raw]
            pts.append(positions[he.origin.raw])
            guard let n = he.next else { break }
            e = n
        }
        if e != startEdge || pts.count < 3 { return [] }
        return pts
    }
}

// MARK: - Edge deletion

extension Mesh2D where ID: Equatable {
    /// Delete an undirected edge by its label.
    /// If the edge is interior (shared by two faces), the two faces are merged.
    /// If the edge is boundary (one face), it is removed from that face.
    /// The half-edges are disconnected in place (indices remain stable but disconnected).
    public mutating func deleteEdge(label: ID) {
        var heIndices: [Int] = []
        for i in topology.halfEdges.indices where edgeLabels[i] == label {
            heIndices.append(i)
        }
        guard !heIndices.isEmpty else { return }

        let heA = heIndices[0]
        let heB = heIndices.count > 1 ? heIndices[1] : nil

        let prevA = topology.halfEdges[heA].prev
        let nextA = topology.halfEdges[heA].next
        let faceA = topology.halfEdges[heA].face

        // Rewire around heA.
        if let p = prevA, let n = nextA {
            topology.halfEdges[p.raw].next = n
            topology.halfEdges[n.raw].prev = p
        }

        if let heB {
            let prevB = topology.halfEdges[heB].prev
            let nextB = topology.halfEdges[heB].next
            let faceB = topology.halfEdges[heB].face

            if let p = prevB, let n = nextB {
                topology.halfEdges[p.raw].next = n
                topology.halfEdges[n.raw].prev = p
            }

            // Interior edge: merge faces. Keep faceA, reassign faceB's half-edges to faceA.
            if let fA = faceA, let fB = faceB, fA != fB {
                if let startB = nextB {
                    var e = startB
                    var visited = Set<HalfEdgeID>()
                    while !visited.contains(e) {
                        visited.insert(e)
                        topology.halfEdges[e.raw].face = fA
                        guard let n = topology.halfEdges[e.raw].next else { break }
                        e = n
                        if e == startB { break }
                    }
                }

                // Stitch the two loops together.
                if let pA = prevA, let nB = nextB {
                    topology.halfEdges[pA.raw].next = nB
                    topology.halfEdges[nB.raw].prev = pA
                }
                if let pB = prevB, let nA = nextA {
                    topology.halfEdges[pB.raw].next = nA
                    topology.halfEdges[nA.raw].prev = pB
                }

                if let nA = nextA {
                    topology.faces[fA.raw].edge = nA
                }
                topology.faces[fB.raw].edge = nil

                let pts = polygon(for: fA)
                faceSignedAreas[fA.raw] = pts.count >= 3 ? Polygon(pts).signedArea : nil
            } else if let fA = faceA, let n = nextA {
                topology.faces[fA.raw].edge = n
            }

            disconnectHalfEdge(heB)
        } else if let fA = faceA, let n = nextA {
            topology.faces[fA.raw].edge = n
        }

        disconnectHalfEdge(heA)

        // Update vertex edge pointers if they pointed to deleted half-edges.
        let originA = topology.halfEdges[heA].origin
        if topology.vertices[originA.raw].edge?.raw == heA {
            // swiftlint:disable:next trailing_closure
            topology.vertices[originA.raw].edge = topology.halfEdges.first(where: { $0.origin == originA && $0.next != nil })?.id
        }
        if let heB {
            let originB = topology.halfEdges[heB].origin
            if topology.vertices[originB.raw].edge?.raw == heB {
                // swiftlint:disable:next trailing_closure
                topology.vertices[originB.raw].edge = topology.halfEdges.first(where: { $0.origin == originB && $0.next != nil })?.id
            }
        }
    }

    private mutating func disconnectHalfEdge(_ idx: Int) {
        topology.halfEdges[idx].twin = nil
        topology.halfEdges[idx].next = nil
        topology.halfEdges[idx].prev = nil
        topology.halfEdges[idx].face = nil
    }
}
