public extension HalfEdgeTopology {
    /// Replace the edge shared by two triangles with the other diagonal of their quad.
    ///
    /// Triangles (a, b, c) and (b, a, d) around edge a–b become (d, c, a) and (c, d, b).
    /// The same half-edge ids are reused: `halfEdge` becomes d → c and its twin c → d.
    ///
    /// - Returns: `false` (and changes nothing) if the edge is on a boundary, either face
    ///   is not a triangle or has holes, the opposite vertices coincide, or edge c–d already exists.
    @discardableResult
    mutating func flipEdge(_ halfEdge: HalfEdgeID) -> Bool {
        guard let twin = halfEdges[halfEdge.raw].twin,
              let face1 = halfEdges[halfEdge.raw].face, let face2 = halfEdges[twin.raw].face,
              faces[face1.raw].holeEdges.isEmpty, faces[face2.raw].holeEdges.isEmpty,
              let next1 = halfEdges[halfEdge.raw].next, let prev1 = halfEdges[halfEdge.raw].prev,
              let next2 = halfEdges[twin.raw].next, let prev2 = halfEdges[twin.raw].prev,
              halfEdges[next1.raw].next == prev1, halfEdges[next2.raw].next == prev2 else {
            return false
        }
        let a = halfEdges[halfEdge.raw].origin
        let b = halfEdges[twin.raw].origin
        let c = halfEdges[prev1.raw].origin
        let d = halfEdges[prev2.raw].origin
        guard c != d, !hasEdge(between: c, and: d) else {
            return false
        }

        // Face 1: d → c (halfEdge), c → a (prev1), a → d (next2)
        halfEdges[halfEdge.raw].origin = d
        link(halfEdge, prev1, next2, face: face1)
        // Face 2: c → d (twin), d → b (prev2), b → c (next1)
        halfEdges[twin.raw].origin = c
        link(twin, prev2, next1, face: face2)

        faces[face1.raw].edge = halfEdge
        faces[face2.raw].edge = twin
        if vertices[a.raw].edge == halfEdge {
            vertices[a.raw].edge = next2
        }
        if vertices[b.raw].edge == twin {
            vertices[b.raw].edge = next1
        }
        return true
    }
}

private extension HalfEdgeTopology {
    mutating func link(_ first: HalfEdgeID, _ second: HalfEdgeID, _ third: HalfEdgeID, face: FaceID) {
        for (edge, next, prev) in [(first, second, third), (second, third, first), (third, first, second)] {
            halfEdges[edge.raw].next = next
            halfEdges[edge.raw].prev = prev
            halfEdges[edge.raw].face = face
        }
    }

    /// Whether a live half-edge runs between `u` and `v` in either direction.
    func hasEdge(between u: VertexID, and v: VertexID) -> Bool {
        halfEdges.contains { edge in
            guard edge.next != nil, let destination = destViaNext(of: edge.id) else {
                return false
            }
            return (edge.origin == u && destination == v) || (edge.origin == v && destination == u)
        }
    }
}

public extension Mesh {
    /// Flip the edge shared by two triangles, keeping per-corner attributes with their vertices.
    ///
    /// See ``HalfEdgeTopology/flipEdge(_:)``.
    @discardableResult
    mutating func flipEdge(_ halfEdge: HalfEdgeTopology.HalfEdgeID) -> Bool {
        guard let twin = topology.halfEdges[halfEdge.raw].twin,
              let prev1 = topology.halfEdges[halfEdge.raw].prev,
              let prev2 = topology.halfEdges[twin.raw].prev else {
            return false
        }
        // After the flip, halfEdge starts at d (old corner prev2) and twin at c (old corner prev1).
        let sources = [(halfEdge.raw, prev2.raw), (twin.raw, prev1.raw)]
        guard topology.flipEdge(halfEdge) else {
            return false
        }
        for (target, source) in sources {
            cornerAttributes.copyCorner(from: source, to: target)
        }
        return true
    }
}
