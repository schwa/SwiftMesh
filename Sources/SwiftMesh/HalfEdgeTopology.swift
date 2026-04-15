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
        public let origin: VertexID
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

extension HalfEdgeTopology {
    /// Validates the consistency of the half-edge topology.
    /// Returns nil if valid, or an error message describing the first issue found.
    public func validate() -> String? {
        // Check 1: All vertices should be referenced by at least one half-edge
        var verticesInEdges = Set<VertexID>()
        for edge in halfEdges {
            verticesInEdges.insert(edge.origin)
        }

        for vertex in vertices {
            if !verticesInEdges.contains(vertex.id) {
                return "Vertex \(vertex.id) is not referenced by any half-edge"
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
