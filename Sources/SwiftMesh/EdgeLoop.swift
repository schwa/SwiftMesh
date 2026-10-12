public extension HalfEdgeTopology {
    /// The edge loop through `halfEdge`, one half-edge per edge, in walking order.
    ///
    /// At each vertex with exactly four edges the loop continues straight through to the
    /// opposite edge (Blender-style). It stops at vertices of any other valence (poles) and
    /// at boundaries. A loop that returns to `halfEdge` is closed; otherwise the result runs
    /// from one stopping vertex to the other and includes `halfEdge`.
    func edgeLoop(from halfEdge: HalfEdgeID) -> [HalfEdgeID] {
        guard halfEdges[halfEdge.raw].next != nil else {
            return []
        }
        var forward: [HalfEdgeID] = [halfEdge]
        var current = halfEdge
        while let next = straightContinuation(of: current) {
            if next == halfEdge {
                return forward // closed loop
            }
            if forward.count > halfEdges.count {
                break
            }
            forward.append(next)
            current = next
        }
        // Open loop: also walk backward from the start (via its twin), then join.
        var backward: [HalfEdgeID] = []
        if let twin = halfEdges[halfEdge.raw].twin {
            current = twin
            while let next = straightContinuation(of: current), backward.count <= halfEdges.count {
                backward.append(next)
                current = next
            }
        }
        // Backward edges run the other way; flip them to the forward direction where possible.
        let reversedBackward = backward.reversed().map { halfEdges[$0.raw].twin ?? $0 }
        return reversedBackward + forward
    }
}

private extension HalfEdgeTopology {
    /// The next outgoing half-edge around `edge`'s origin (crossing into the neighboring face).
    func rotate(_ outgoing: HalfEdgeID) -> HalfEdgeID? {
        guard let previous = halfEdges[outgoing.raw].prev else {
            return nil
        }
        return halfEdges[previous.raw].twin
    }

    /// Number of edges at a vertex, or nil if its fan is open (boundary) or broken.
    func closedValence(of outgoing: HalfEdgeID) -> Int? {
        var count = 0
        var current = outgoing
        repeat {
            count += 1
            guard count <= halfEdges.count, let next = rotate(current) else {
                return nil
            }
            current = next
        } while current != outgoing
        return count
    }

    /// The half-edge continuing `edge` straight through its destination, or nil at a pole or boundary.
    func straightContinuation(of edge: HalfEdgeID) -> HalfEdgeID? {
        guard let back = halfEdges[edge.raw].twin, closedValence(of: back) == 4 else {
            return nil
        }
        // From the edge pointing back, two steps around the vertex is straight across.
        return rotate(back).flatMap(rotate)
    }
}
