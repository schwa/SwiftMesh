import Foundation

// MARK: - HalfEdgeTopology

/// A pure combinatorial half-edge topology structure.
///
/// Stores only vertex IDs, half-edges, and faces with their wiring
/// (next/prev/twin). No positions or geometry — pair with external
/// attribute storage (positions, normals, UVs, etc.) to form a mesh.
public struct HalfEdgeTopology: Sendable, Equatable {
    // Stable ids
    public struct VertexID: Hashable, Sendable { public let raw: Int; public init(raw: Int) { self.raw = raw } }
    public struct HalfEdgeID: Hashable, Sendable { public let raw: Int; public init(raw: Int) { self.raw = raw } }
    public struct FaceID: Hashable, Sendable { public let raw: Int; public init(raw: Int) { self.raw = raw } }

    public struct Vertex: Sendable, Equatable {
        public let id: VertexID
        public var edge: HalfEdgeID? // one outgoing
    }

    public struct HalfEdge: Sendable, Equatable {
        public let id: HalfEdgeID
        public var origin: VertexID
        public var twin: HalfEdgeID?
        public var next: HalfEdgeID?
        public var prev: HalfEdgeID?
        public var face: FaceID?
    }

    public struct Face: Sendable, Equatable {
        public let id: FaceID
        public var edge: HalfEdgeID? // outer boundary edge
        public var holeEdges: [HalfEdgeID] = [] // one half-edge per hole loop
    }

    public var vertices: [Vertex] = []
    public private(set) var halfEdges: [HalfEdge] = []
    public private(set) var faces: [Face] = []

    public init() {}

    /// A face definition for building topology from indexed vertex references.
    public struct FaceDefinition: Sendable {
        public var outer: [Int]
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

        // Map (origin, dest) -> halfEdgeID for twin linking
        // Encode directed edge as origin * vertexCount + dest
        var edgeMap: [Int: HalfEdgeID] = [:]

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

                let forwardKey = originIdx * vertexCount + destIdx
                let reverseKey = destIdx * vertexCount + originIdx

                var twin: HalfEdgeID?
                if let twinID = edgeMap[reverseKey] {
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

                edgeMap[forwardKey] = heID

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
    public var message: String

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

        let originA = halfEdges[heA].origin
        if vertices[originA.raw].edge?.raw == heA {
            vertices[originA.raw].edge = halfEdges.first { $0.origin == originA && $0.next != nil }?.id
        }
        if let heB {
            let originB = halfEdges[heB].origin
            if vertices[originB.raw].edge?.raw == heB {
                vertices[originB.raw].edge = halfEdges.first { $0.origin == originB && $0.next != nil }?.id
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
        let he = halfEdges[heID.raw]
        let vertexA = he.origin // kept
        guard let vertexB = destViaNext(of: heID) else {
            return nil
        }

        // Repoint all half-edges originating from B to originate from A
        for i in halfEdges.indices where halfEdges[i].origin == vertexB {
            halfEdges[i].origin = vertexA
        }

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
                        tombstoneHalfEdge(hid)
                    }
                } else {
                    // Unexpected topology — tombstone the self-loop at minimum
                    tombstoneHalfEdge(selfLoopHE)
                }
            } else {
                // Multiple degenerate edges or none — just tombstone the whole face's edges
                for hid in loop {
                    if let twinID = halfEdges[hid.raw].twin {
                        halfEdges[twinID.raw].twin = nil
                    }
                    tombstoneHalfEdge(hid)
                }
            }

            // Tombstone the face
            faces[faceID.raw].edge = nil
        }

        // Tombstone vertex B
        vertices[vertexB.raw].edge = nil

        // Fix vertex A's outgoing edge to point to a live half-edge
        vertices[vertexA.raw].edge = halfEdges.first { $0.origin == vertexA && $0.next != nil }?.id

        // Fix outgoing edges for all neighbors whose edge ref may now be dead
        for i in vertices.indices where vertices[i].edge != nil {
            let eid = vertices[i].edge!
            if halfEdges[eid.raw].next == nil {
                vertices[i].edge = halfEdges.first { $0.origin == vertices[i].id && $0.next != nil }?.id
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
        var ids: [VertexID] = []
        var current = startEdge
        var visited = Set<HalfEdgeID>()
        while !visited.contains(current) {
            visited.insert(current)
            ids.append(halfEdges[current.raw].origin)
            guard let next = halfEdges[current.raw].next else {
                break
            }
            current = next
        }
        if current != startEdge || ids.count < 3 {
            return []
        }
        return ids
    }

    func collectHalfEdgeLoop(startEdge: HalfEdgeID) -> [HalfEdgeID] {
        var ids: [HalfEdgeID] = []
        var current = startEdge
        var visited = Set<HalfEdgeID>()
        while !visited.contains(current) {
            visited.insert(current)
            ids.append(current)
            guard let next = halfEdges[current.raw].next else {
                break
            }
            current = next
        }
        if current != startEdge || ids.count < 3 {
            return []
        }
        return ids
    }
}
