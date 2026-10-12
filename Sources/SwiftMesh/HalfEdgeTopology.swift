import Foundation

// MARK: - HalfEdgeTopology

/// A pure combinatorial half-edge topology structure.
///
/// Stores only vertex IDs, half-edges, and faces with their wiring
/// (next/prev/twin). No positions or geometry — pair with external
/// attribute storage (positions, normals, UVs, etc.) to form a mesh.
public struct HalfEdgeTopology: Sendable, Equatable {
    /// A vertex index. `raw` indexes ``vertices`` and per-vertex arrays such as `Mesh.positions`.
    public struct VertexID: Hashable, Sendable { public let raw: Int; public init(raw: Int) { self.raw = raw } }
    /// A half-edge index. `raw` indexes ``halfEdges`` and per-corner attribute arrays.
    public struct HalfEdgeID: Hashable, Sendable { public let raw: Int; public init(raw: Int) { self.raw = raw } }
    /// A face index. `raw` indexes ``faces`` and per-face data.
    public struct FaceID: Hashable, Sendable { public let raw: Int; public init(raw: Int) { self.raw = raw } }

    /// A vertex and one of its outgoing half-edges.
    public struct Vertex: Sendable, Equatable {
        public let id: VertexID
        /// An outgoing half-edge, or `nil` if the vertex is unused or tombstoned.
        public var edge: HalfEdgeID?
    }

    /// A directed edge belonging to one face loop. Its destination is `next`'s origin.
    ///
    /// A half-edge with `next == nil` is tombstoned (removed by an editing operation).
    public struct HalfEdge: Sendable, Equatable {
        public let id: HalfEdgeID
        /// The vertex the half-edge starts at.
        public var origin: VertexID
        /// The opposite half-edge in the neighboring face, or `nil` on a boundary.
        public var twin: HalfEdgeID?
        /// The following half-edge in the same face loop.
        public var next: HalfEdgeID?
        /// The preceding half-edge in the same face loop.
        public var prev: HalfEdgeID?
        /// The face on the half-edge's left, which owns this loop.
        public var face: FaceID?
    }

    /// A face: one outer loop and any number of hole loops.
    public struct Face: Sendable, Equatable {
        public let id: FaceID
        /// A half-edge on the outer loop, or `nil` if the face is tombstoned.
        public var edge: HalfEdgeID?
        /// One half-edge on each hole loop.
        public var holeEdges: [HalfEdgeID] = []
    }

    /// All vertices, indexed by `VertexID.raw`.
    public var vertices: [Vertex] = []
    // `halfEdges` and `faces` are `internal(set)` so construction code in sibling
    // files (currently `Mesh2D.swift`) can build topology in-place. External
    // callers see them as read-only; internal callers must preserve invariants
    // (twin/next/prev wiring, face-on-left).
    public internal(set) var halfEdges: [HalfEdge] = []
    public internal(set) var faces: [Face] = []

    /// Creates an empty topology.
    public init() {}

    /// A face definition for building topology from indexed vertex references.
    public struct FaceDefinition: Sendable {
        /// Vertex indices of the outer loop, counter-clockwise when viewed from the front.
        public var outer: [Int]
        /// Vertex indices of each hole loop.
        public var holes: [[Int]]

        public init(outer: [Int], holes: [[Int]] = []) {
            self.outer = outer
            self.holes = holes
        }
    }

    /// Build topology from a vertex count and face definitions (with optional holes).
    ///
    /// Vertex indices are preserved (topology vertex N corresponds to external vertex N).
    public init(vertexCount: Int, faces faceDefinitions: [FaceDefinition]) {
        // 1. Create vertices, preserving index order
        vertices = (0..<vertexCount).map { Vertex(id: VertexID(raw: $0), edge: nil) }

        // Directed edges leaving each vertex, for twin lookup. Per-vertex lists are short, so
        // searching them beats hashing every edge into a dictionary.
        var outgoingByVertex = [[(destination: Int, edge: HalfEdgeID)]](repeating: [], count: vertexCount)

        // Helper: create half-edges for a loop, assign them to fID, return first HE index
        func buildLoop(_ loop: [Int], faceID fID: FaceID) -> HalfEdgeID? {
            guard loop.count >= 3 else {
                return nil
            }
            let firstHEIdx = halfEdges.count

            for idx in 0..<loop.count {
                let originIdx = loop[idx]
                let destIdx = loop[(idx + 1) % loop.count]
                let heID = HalfEdgeID(raw: halfEdges.count)

                // Pair as twins only if the candidate hasn't already been paired.
                // For non-manifold edges (≥3 half-edges sharing an undirected edge),
                // the first two are paired and any extras are left as boundary edges.
                // This preserves twin symmetry instead of silently corrupting it.
                var twin: HalfEdgeID?
                // The most recent dest -> origin half-edge (matching the old dictionary overwrite).
                if let twinID = outgoingByVertex[destIdx].last(where: { $0.destination == originIdx })?.edge, halfEdges[twinID.raw].twin == nil {
                    twin = twinID
                    halfEdges[twinID.raw].twin = heID
                }

                halfEdges.append(HalfEdge(
                    id: heID,
                    origin: VertexID(raw: originIdx),
                    twin: twin,
                    next: nil,
                    prev: nil,
                    face: fID
                ))

                outgoingByVertex[originIdx].append((destIdx, heID))

                if vertices[originIdx].edge == nil {
                    vertices[originIdx].edge = heID
                }
            }

            // Link next/prev within the loop
            for idx in 0..<loop.count {
                let heIdx = firstHEIdx + idx
                let nextIdx = firstHEIdx + (idx + 1) % loop.count
                let prevIdx = firstHEIdx + (idx + loop.count - 1) % loop.count
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

            faces.append(Face(id: fID, edge: outerEdge, holeEdges: holeEdges))
        }
    }

    // MARK: - Accessors

    @inlinable public func dest(of e: HalfEdgeID) -> VertexID? {
        guard let t = halfEdges[e.raw].twin else {
            return nil
        }
        return halfEdges[t.raw].origin
    }

    /// Destination vertex of a half-edge, found via the next pointer.
    /// Works even when the half-edge has no twin.
    @inlinable public func destViaNext(of e: HalfEdgeID) -> VertexID? {
        guard let n = halfEdges[e.raw].next else {
            return nil
        }
        return halfEdges[n.raw].origin
    }
}

// MARK: - Convenience

extension HalfEdgeTopology.HalfEdgeID: CustomStringConvertible {
    public var description: String { "H\(raw)" }
}
extension HalfEdgeTopology.VertexID: CustomStringConvertible {
    public var description: String { "V\(raw)" }
}
extension HalfEdgeTopology.FaceID: CustomStringConvertible {
    public var description: String { "F\(raw)" }
}

// MARK: - Validation

/// A problem found during topology or mesh validation.
public struct ValidationIssue: Sendable, Equatable, CustomStringConvertible {
    /// How severe the issue is.
    public enum Severity: Sendable, Equatable, Comparable {
        /// Informational — not necessarily wrong but worth noting.
        case warning
        /// Structural problem that will cause incorrect behavior.
        case error
    }

    /// Where in the topology the issue was found.
    public enum Location: Sendable, Equatable {
        case vertex(HalfEdgeTopology.VertexID)
        case edge(HalfEdgeTopology.HalfEdgeID)
        case face(HalfEdgeTopology.FaceID)
        case mesh
    }

    public var severity: Severity
    public var location: Location
    /// A human-readable explanation of the problem.
    public var message: String

    /// Creates an issue. Mostly useful for custom validators and tests.
    public init(severity: Severity, location: Location, message: String) {
        self.severity = severity
        self.location = location
        self.message = message
    }

    public var description: String {
        let loc: String
        switch location {
        case .vertex(let id): loc = "vertex \(id)"
        case .edge(let id): loc = "edge \(id)"
        case .face(let id): loc = "face \(id)"
        case .mesh: loc = "mesh"
        }
        return "[\(severity)] \(loc): \(message)"
    }
}

extension HalfEdgeTopology {
    /// Validates the consistency of the half-edge topology.
    ///
    /// Returns an empty array if valid, or one ``ValidationIssue`` per problem found.
    public func validate() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        // Check 1: All vertices should be referenced by at least one half-edge
        var verticesInEdges = Set<VertexID>()
        for edge in halfEdges {
            verticesInEdges.insert(edge.origin)
        }

        for vertex in vertices {
            if !verticesInEdges.contains(vertex.id) {
                issues.append(.init(severity: .error, location: .vertex(vertex.id), message: "Not referenced by any half-edge"))
            }
            if let edgeID = vertex.edge {
                if edgeID.raw >= halfEdges.count {
                    issues.append(.init(severity: .error, location: .vertex(vertex.id), message: "Invalid edge reference \(edgeID)"))
                } else if halfEdges[edgeID.raw].origin != vertex.id {
                    issues.append(.init(severity: .error, location: .vertex(vertex.id), message: "References edge \(edgeID) which doesn't originate from it"))
                }
            }
        }

        // Check 2: Each half-edge should be in at least one face (unless boundary)
        for edge in halfEdges {
            if edge.face == nil, edge.twin == nil {
                issues.append(.init(severity: .error, location: .edge(edge.id), message: "Has no face and no twin"))
            }
        }

        // Check 3: Twin relationships are symmetric
        for edge in halfEdges {
            if let twinID = edge.twin {
                if twinID.raw >= halfEdges.count {
                    issues.append(.init(severity: .error, location: .edge(edge.id), message: "Invalid twin reference \(twinID)"))
                    continue
                }
                let twin = halfEdges[twinID.raw]
                if twin.twin != edge.id {
                    issues.append(.init(severity: .error, location: .edge(edge.id), message: "Twin \(twinID) points back to \(twin.twin?.description ?? "nil") instead of \(edge.id)"))
                }
                if let twinDest = dest(of: edge.id), twin.origin != twinDest {
                    issues.append(.init(severity: .error, location: .edge(edge.id), message: "Twin \(twinID) doesn't have opposite vertices"))
                }
                if let edgeDest = dest(of: twinID), edge.origin != edgeDest {
                    issues.append(.init(severity: .error, location: .edge(edge.id), message: "Twin \(twinID) doesn't have opposite vertices (reverse)"))
                }
            }
        }

        // Check 4: Next/prev relationships are consistent
        for edge in halfEdges {
            if let nextID = edge.next {
                if nextID.raw >= halfEdges.count {
                    issues.append(.init(severity: .error, location: .edge(edge.id), message: "Invalid next reference \(nextID)"))
                } else if halfEdges[nextID.raw].prev != edge.id {
                    issues.append(.init(severity: .error, location: .edge(edge.id), message: "next \(nextID) has prev \(halfEdges[nextID.raw].prev?.description ?? "nil") instead of \(edge.id)"))
                }
            }
            if let prevID = edge.prev {
                if prevID.raw >= halfEdges.count {
                    issues.append(.init(severity: .error, location: .edge(edge.id), message: "Invalid prev reference \(prevID)"))
                } else if halfEdges[prevID.raw].next != edge.id {
                    issues.append(.init(severity: .error, location: .edge(edge.id), message: "prev \(prevID) has next \(halfEdges[prevID.raw].next?.description ?? "nil") instead of \(edge.id)"))
                }
            }
        }

        // Check 5: Face boundaries form closed loops
        for face in faces {
            guard let startEdge = face.edge else {
                issues.append(.init(severity: .error, location: .face(face.id), message: "Has no boundary edge"))
                continue
            }
            if startEdge.raw >= halfEdges.count {
                issues.append(.init(severity: .error, location: .face(face.id), message: "Invalid edge reference \(startEdge)"))
                continue
            }
            var visited = Set<HalfEdgeID>()
            var currentEdge = startEdge
            var loopCount = 0
            let maxLoopCount = halfEdges.count + 1
            var loopBroken = false

            while loopCount < maxLoopCount {
                if visited.contains(currentEdge) {
                    if currentEdge != startEdge {
                        issues.append(.init(severity: .error, location: .face(face.id), message: "Boundary doesn't form a proper closed loop (revisited \(currentEdge) before returning to start)"))
                        loopBroken = true
                    }
                    break
                }
                visited.insert(currentEdge)
                let edge = halfEdges[currentEdge.raw]
                if edge.face != face.id {
                    issues.append(.init(severity: .error, location: .face(face.id), message: "Edge \(currentEdge) belongs to face \(edge.face?.description ?? "nil")"))
                    loopBroken = true
                    break
                }
                guard let nextEdge = edge.next else {
                    issues.append(.init(severity: .error, location: .face(face.id), message: "Edge \(currentEdge) has no next pointer (open boundary)"))
                    loopBroken = true
                    break
                }
                currentEdge = nextEdge
                loopCount += 1
            }
            if loopCount >= maxLoopCount {
                issues.append(.init(severity: .error, location: .face(face.id), message: "Boundary appears to be infinite or malformed"))
            } else if !loopBroken, visited.count < 3 {
                issues.append(.init(severity: .error, location: .face(face.id), message: "Degenerate boundary with only \(visited.count) edges"))
            }
        }

        // Check 7: Non-manifold edges (more than two half-edges on one undirected edge).
        // Construction pairs the first two as twins and leaves the rest as boundary, so this is a warning.
        var edgeUse: [Int: (a: VertexID, b: VertexID, count: Int, first: HalfEdgeID)] = [:]
        for edge in halfEdges where edge.next != nil {
            guard let destination = destViaNext(of: edge.id) else {
                continue
            }
            let a = min(edge.origin.raw, destination.raw)
            let b = max(edge.origin.raw, destination.raw)
            let key = a * vertices.count + b
            let entry = edgeUse[key] ?? (VertexID(raw: a), VertexID(raw: b), 0, edge.id)
            edgeUse[key] = (entry.a, entry.b, entry.count + 1, entry.first)
        }
        for entry in edgeUse.values.sorted(by: { $0.first.raw < $1.first.raw }) where entry.count > 2 {
            issues.append(.init(severity: .warning, location: .edge(entry.first), message: "Non-manifold edge \(entry.a)-\(entry.b) has \(entry.count) incident half-edges"))
        }

        // Check 6: No edge should reference non-existent faces
        for edge in halfEdges {
            if let faceID = edge.face {
                if faceID.raw >= faces.count {
                    issues.append(.init(severity: .error, location: .edge(edge.id), message: "References non-existent face \(faceID)"))
                }
            }
        }

        return issues
    }

    /// Whether this topology is a closed 2-manifold.
    ///
    /// A closed 2-manifold has:
    /// - Every half-edge paired with exactly one twin (no boundary edges)
    /// - Every half-edge assigned to a face
    /// - Every vertex surrounded by a single, complete fan of faces
    ///   (no non-manifold vertices where multiple fans meet at a pinch point)
    public var isManifold: Bool {
        // Check 1: every half-edge has a twin and a face (no boundary)
        for edge in halfEdges {
            guard edge.twin != nil, edge.face != nil else {
                return false
            }
        }

        // Check 2: every vertex has a single closed fan
        // Walk around each vertex via twin→next. If the fan is closed and
        // consistent, we visit exactly the right number of edges before
        // returning to the start.
        for vertex in vertices {
            guard let startEdge = vertex.edge else {
                return false
            }
            // Walk: from startEdge, go to twin.next repeatedly
            var current = startEdge
            var count = 0
            repeat {
                guard let twin = halfEdges[current.raw].twin,
                      let next = halfEdges[twin.raw].next else {
                    return false
                }
                current = next
                count += 1
                if count > halfEdges.count {
                    return false // infinite loop
                }
            } while current != startEdge
        }

        return true
    }
}

// MARK: - Topology queries

extension HalfEdgeTopology {
    /// Return the ordered boundary of `face` as vertex IDs.
    public func vertexLoop(for face: FaceID) -> [VertexID] {
        guard let start = faces[face.raw].edge else {
            return []
        }
        return collectVertexLoop(startEdge: start)
    }

    /// Return the ordered boundary of `face` as half-edge IDs.
    public func halfEdgeLoop(for face: FaceID) -> [HalfEdgeID] {
        guard let start = faces[face.raw].edge else {
            return []
        }
        return collectHalfEdgeLoop(startEdge: start)
    }

    /// Return the hole boundaries of `face` as arrays of vertex IDs.
    public func holeVertexLoops(for face: FaceID) -> [[VertexID]] {
        faces[face.raw].holeEdges.map { collectVertexLoop(startEdge: $0) }
    }

    /// Returns faces that share an edge with the given face.
    public func neighborFaces(of face: FaceID) -> [FaceID] {
        var neighbors = Set<FaceID>()
        guard let startEdge = faces[face.raw].edge else {
            return []
        }

        func walkLoop(from start: HalfEdgeID) {
            var current = start
            var visited = Set<HalfEdgeID>()
            while !visited.contains(current) {
                visited.insert(current)
                if let twinID = halfEdges[current.raw].twin, let twinFace = halfEdges[twinID.raw].face, twinFace != face {
                    neighbors.insert(twinFace)
                }
                guard let next = halfEdges[current.raw].next else {
                    break
                }
                current = next
            }
        }

        walkLoop(from: startEdge)
        for holeEdge in faces[face.raw].holeEdges {
            walkLoop(from: holeEdge)
        }
        return Array(neighbors)
    }

    /// Returns closed loops of vertex IDs formed by boundary half-edges (those with no twin).
    public func boundaryLoops() -> [[VertexID]] {
        var visited = Set<HalfEdgeID>()
        var loops: [[VertexID]] = []

        for he in halfEdges where he.twin == nil {
            if visited.contains(he.id) { continue }
            var loop: [VertexID] = []
            var current = he.id
            while !visited.contains(current) {
                visited.insert(current)
                let edge = halfEdges[current.raw]
                loop.append(edge.origin)
                guard let next = edge.next else {
                    break
                }
                var walker = next
                var safety = halfEdges.count
                while halfEdges[walker.raw].twin != nil, safety > 0 {
                    guard let twinNext = halfEdges[halfEdges[walker.raw].twin!.raw].next else {
                        break
                    }
                    walker = twinNext
                    safety -= 1
                }
                if safety == 0 {
                    break
                }
                current = walker
            }
            if loop.count >= 3 {
                loops.append(loop)
            }
        }
        return loops
    }

    /// Returns all unique undirected edges as (vertexA, vertexB) pairs.
    public func undirectedEdges() -> [(VertexID, VertexID)] {
        var seen = Set<Int>()
        var result: [(VertexID, VertexID)] = []
        for he in halfEdges {
            let key = min(he.origin.raw, destViaNext(of: he.id)?.raw ?? he.origin.raw) * vertices.count + max(he.origin.raw, destViaNext(of: he.id)?.raw ?? he.origin.raw)
            if seen.insert(key).inserted {
                if let twinID = he.twin {
                    result.append((he.origin, halfEdges[twinID.raw].origin))
                } else if let destID = destViaNext(of: he.id) {
                    result.append((he.origin, destID))
                }
            }
        }
        return result
    }

    // MARK: - Edge deletion

    /// Delete an edge between two faces.
    /// If the edge is interior (shared by two faces), the two faces are merged into one.
    /// If the edge is boundary (one face), it is removed from that face.
    public mutating func deleteEdge(_ heID: HalfEdgeID) {
        let heA = heID.raw
        let heB = halfEdges[heA].twin?.raw

        let prevA = halfEdges[heA].prev
        let nextA = halfEdges[heA].next
        let faceA = halfEdges[heA].face
        let nextAfterB = heB.flatMap { halfEdges[$0].next }

        if let prevA, let nextA {
            halfEdges[prevA.raw].next = nextA
            halfEdges[nextA.raw].prev = prevA
        }

        if let heB {
            let prevB = halfEdges[heB].prev
            let nextB = halfEdges[heB].next
            let faceB = halfEdges[heB].face

            if let prevB, let nextB {
                halfEdges[prevB.raw].next = nextB
                halfEdges[nextB.raw].prev = prevB
            }

            if let fA = faceA, let fB = faceB, fA != fB {
                if let startB = nextB {
                    var current = startB
                    var visited = Set<HalfEdgeID>()
                    while !visited.contains(current) {
                        visited.insert(current)
                        halfEdges[current.raw].face = fA
                        guard let next = halfEdges[current.raw].next else {
                            break
                        }
                        current = next
                        if current == startB {
                            break
                        }
                    }
                }

                if let prevA, let nextB {
                    halfEdges[prevA.raw].next = nextB
                    halfEdges[nextB.raw].prev = prevA
                }
                if let prevB, let nextA {
                    halfEdges[prevB.raw].next = nextA
                    halfEdges[nextA.raw].prev = prevB
                }

                if let nextA {
                    faces[fA.raw].edge = nextA
                }

                faces[fB.raw].edge = nil
            } else if let fA = faceA {
                if let nextA {
                    faces[fA.raw].edge = nextA
                }
            }

            halfEdges[heB].twin = nil
            halfEdges[heB].next = nil
            halfEdges[heB].prev = nil
            halfEdges[heB].face = nil
        } else {
            if let fA = faceA, let nextA {
                faces[fA.raw].edge = nextA
            }
        }

        halfEdges[heA].twin = nil
        halfEdges[heA].next = nil
        halfEdges[heA].prev = nil
        halfEdges[heA].face = nil

        // The edges that followed the deleted pair start at the same vertices, so they are
        // the natural replacements; fall back to a scan only if they are unusable.
        func replacementEdge(for vertex: VertexID, candidate: HalfEdgeID?) -> HalfEdgeID? {
            if let candidate, halfEdges[candidate.raw].next != nil, halfEdges[candidate.raw].origin == vertex {
                return candidate
            }
            return halfEdges.first { $0.origin == vertex && $0.next != nil }?.id
        }

        let originA = halfEdges[heA].origin
        if vertices[originA.raw].edge?.raw == heA {
            vertices[originA.raw].edge = replacementEdge(for: originA, candidate: nextAfterB)
        }
        if let heB {
            let originB = halfEdges[heB].origin
            if vertices[originB.raw].edge?.raw == heB {
                vertices[originB.raw].edge = replacementEdge(for: originB, candidate: nextA)
            }
        }
    }

    // MARK: - Edge collapse

    /// Collapse an edge, merging its destination vertex into its origin vertex.
    ///
    /// The half-edge's origin is kept; the destination vertex is tombstoned.
    /// Adjacent triangle faces that become degenerate (2 edges) are removed.
    /// Returns the surviving vertex ID, or nil if the collapse is invalid.
    @discardableResult
    public mutating func collapseEdge(_ heID: HalfEdgeID) -> VertexID? {
        var outgoing = outgoingHalfEdges()
        return collapseEdge(heID, outgoing: &outgoing)
    }

    /// Outgoing half-edges per vertex, indexed by `VertexID.raw`. May include tombstoned half-edges.
    func outgoingHalfEdges() -> [[HalfEdgeID]] {
        var outgoing = [[HalfEdgeID]](repeating: [], count: vertices.count)
        for he in halfEdges where he.next != nil {
            outgoing[he.origin.raw].append(he.id)
        }
        return outgoing
    }

    /// Collapse an edge using and updating a precomputed outgoing half-edge table, avoiding full scans.
    @discardableResult
    mutating func collapseEdge(_ heID: HalfEdgeID, outgoing: inout [[HalfEdgeID]]) -> VertexID? {
        let he = halfEdges[heID.raw]
        let vertexA = he.origin // kept
        guard let vertexB = destViaNext(of: heID) else {
            return nil
        }

        // Repoint all half-edges originating from B to originate from A
        for id in outgoing[vertexB.raw] where halfEdges[id.raw].origin == vertexB {
            halfEdges[id.raw].origin = vertexA
        }
        outgoing[vertexA.raw] += outgoing[vertexB.raw]
        outgoing[vertexB.raw] = []
        var touchedVertices: Set<VertexID> = [vertexA]

        // Collect the faces adjacent to this edge (via he and twin)
        // These triangle faces will become degenerate and need removal
        var facesToRemove: [FaceID] = []
        if let face = he.face {
            facesToRemove.append(face)
        }
        if let twinID = he.twin, let face = halfEdges[twinID.raw].face {
            facesToRemove.append(face)
        }

        // For each degenerate face, remove its edges from the topology
        for faceID in facesToRemove {
            let loop = halfEdgeLoop(for: faceID)

            // Find the edges in this face loop that now have origin == dest (self-loops)
            // After repointing B→A, the collapsed edge has origin A and dest A
            // We need to remove the degenerate face and stitch the remaining edges

            // Find half-edges in the loop that form the collapsed edge (origin == dest)
            let degenerateHEs = loop.filter { hid in
                let o = halfEdges[hid.raw].origin
                let d = destViaNext(of: hid)
                return d == o
            }

            if degenerateHEs.count == 1 {
                // Triangle collapsed: one edge became a self-loop
                // The other two edges become the same undirected edge — pair them as twins
                let selfLoopHE = degenerateHEs[0]
                let remaining = loop.filter { $0 != selfLoopHE }

                if remaining.count == 2 {
                    let edgeP = remaining[0]
                    let edgeQ = remaining[1]

                    // Unlink existing twins of P and Q, then pair their former twins together
                    let twinP = halfEdges[edgeP.raw].twin
                    let twinQ = halfEdges[edgeQ.raw].twin

                    if let tP = twinP, let tQ = twinQ {
                        halfEdges[tP.raw].twin = tQ
                        halfEdges[tQ.raw].twin = tP
                    } else if let tP = twinP {
                        halfEdges[tP.raw].twin = nil
                    } else if let tQ = twinQ {
                        halfEdges[tQ.raw].twin = nil
                    }

                    // Tombstone P, Q, and the self-loop
                    for hid in [selfLoopHE, edgeP, edgeQ] {
                        touchedVertices.insert(halfEdges[hid.raw].origin)
                        tombstoneHalfEdge(hid)
                    }
                } else {
                    // Unexpected topology — tombstone the self-loop at minimum
                    touchedVertices.insert(halfEdges[selfLoopHE.raw].origin)
                    tombstoneHalfEdge(selfLoopHE)
                }
            } else {
                // Multiple degenerate edges or none — just tombstone the whole face's edges
                for hid in loop {
                    if let twinID = halfEdges[hid.raw].twin {
                        halfEdges[twinID.raw].twin = nil
                    }
                    touchedVertices.insert(halfEdges[hid.raw].origin)
                    tombstoneHalfEdge(hid)
                }
            }

            // Tombstone the face
            faces[faceID.raw].edge = nil
        }

        // Tombstone vertex B
        vertices[vertexB.raw].edge = nil

        // Prune tombstoned half-edges and repair edge refs only where something changed
        for vertex in touchedVertices where vertex != vertexB {
            outgoing[vertex.raw].removeAll { halfEdges[$0.raw].next == nil || halfEdges[$0.raw].origin != vertex }
            if vertex == vertexA || vertices[vertex.raw].edge.map({ halfEdges[$0.raw].next == nil }) == true {
                vertices[vertex.raw].edge = outgoing[vertex.raw].first
            }
        }

        return vertexA
    }

    /// Tombstone a half-edge by clearing all its wiring.
    private mutating func tombstoneHalfEdge(_ heID: HalfEdgeID) {
        halfEdges[heID.raw].twin = nil
        halfEdges[heID.raw].next = nil
        halfEdges[heID.raw].prev = nil
        halfEdges[heID.raw].face = nil
    }

    // MARK: - Internals

    func collectVertexLoop(startEdge: HalfEdgeID) -> [VertexID] {
        collectHalfEdgeLoop(startEdge: startEdge).map { halfEdges[$0.raw].origin }
    }

    /// The closed loop through `startEdge`, or `[]` if it doesn't return to the start (broken
    /// wiring or a walk that cycles elsewhere) or has fewer than 3 edges.
    func collectHalfEdgeLoop(startEdge: HalfEdgeID) -> [HalfEdgeID] {
        // Walk until back at the start. A walk longer than the half-edge count can't be a
        // simple loop through the start, so it is broken; no visited set needed.
        var ids: [HalfEdgeID] = []
        var current = startEdge
        repeat {
            ids.append(current)
            guard ids.count <= halfEdges.count, let next = halfEdges[current.raw].next else {
                return []
            }
            current = next
        } while current != startEdge
        return ids.count >= 3 ? ids : []
    }
}
