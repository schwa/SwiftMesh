import simd

public extension Mesh {
    /// Bevel edges with a single flat face of width about `distance`.
    ///
    /// Each chamfered edge becomes a quad strip. Faces shrink away from chamfered edges:
    /// a corner between two chamfered edges moves `distance` inside both edges (in the face
    /// plane); otherwise the corner slides `distance` along each unchamfered edge, so faces
    /// on either side share the new point. Vertices touching chamfered edges get a patch
    /// polygon when at least three distinct points surround them (for example a cube
    /// corner with all three edges chamfered); with one chamfered edge the adjacent face
    /// absorbs the cut instead.
    ///
    /// With `segments` > 1 each strip curves into a rounded fillet: N quads along a quadratic
    /// Bezier from one side to the other, with the original edge as the control point, so the
    /// round meets both faces tangentially. Vertex patches follow the arcs; they are simple
    /// polygons, not true spherical blends.
    ///
    /// - Parameters:
    ///   - distance: How far the cut reaches from each chamfered edge along the faces.
    ///   - segments: Quads across each strip. 1 is a flat chamfer; more gives a fillet.
    ///   - edges: Half-edges to chamfer (either direction of an edge selects it). `nil`
    ///     chamfers every edge.
    ///   - attributes: Attributes to derive on the result. Input per-corner attributes
    ///     are not carried over.
    /// - Returns: The chamfered mesh, or `nil` if the mesh is not a closed manifold.
    func chamfered(distance: Float, segments: Int = 1, edges: Set<HalfEdgeTopology.HalfEdgeID>? = nil, attributes: MeshAttributes = []) -> Mesh? {
        guard isManifold, segments >= 1 else {
            return nil
        }
        let topology = topology
        func isChamfered(_ halfEdge: HalfEdgeTopology.HalfEdgeID) -> Bool {
            guard let edges else {
                return true
            }
            return edges.contains(halfEdge) || topology.halfEdges[halfEdge.raw].twin.map(edges.contains) == true
        }

        var newPositions: [SIMD3<Float>] = []
        var pointIndex: [String: Int] = [:]
        func point(_ key: String, _ make: () -> SIMD3<Float>) -> Int {
            if let existing = pointIndex[key] {
                return existing
            }
            pointIndex[key] = newPositions.count
            newPositions.append(make())
            return newPositions.count - 1
        }
        func position(_ vertex: HalfEdgeTopology.VertexID) -> SIMD3<Float> {
            positions[vertex.raw]
        }
        /// Point slid from the edge's origin toward its destination.
        func slid(_ halfEdge: HalfEdgeTopology.HalfEdgeID, from vertex: HalfEdgeTopology.VertexID) -> Int {
            let edge = topology.halfEdges[halfEdge.raw]
            let other = edge.origin == vertex ? topology.destViaNext(of: halfEdge)! : edge.origin
            return point("s\(vertex.raw)-\(other.raw)") {
                let direction = position(other) - position(vertex)
                let length = simd_length(direction)
                return position(vertex) + direction / length * min(distance, length * 0.45)
            }
        }

        // Points replacing each corner (keyed by the half-edge leaving that corner), ordered
        // from the incoming-edge side to the outgoing-edge side.
        var cornerPoints: [Int: [Int]] = [:]
        for face in topology.faces where face.edge != nil {
            let normal = faceNormal(face.id)
            for outgoing in topology.halfEdgeLoop(for: face.id) {
                let incoming = topology.halfEdges[outgoing.raw].prev!
                let vertex = topology.halfEdges[outgoing.raw].origin
                let incomingChamfered = isChamfered(incoming)
                let outgoingChamfered = isChamfered(outgoing)
                let anyAtVertex = topology.vertexRing(vertex).contains(where: isChamfered)
                switch (incomingChamfered, outgoingChamfered) {
                case (true, true):
                    let u = topology.halfEdges[incoming.raw].origin
                    let w = topology.destViaNext(of: outgoing)!
                    cornerPoints[outgoing.raw] = [point("q\(face.id.raw)-\(vertex.raw)") {
                        offsetCorner(at: position(vertex), from: position(u), to: position(w), normal: normal, distance: distance)
                    }]
                case (true, false):
                    cornerPoints[outgoing.raw] = [slid(outgoing, from: vertex)]
                case (false, true):
                    cornerPoints[outgoing.raw] = [slid(incoming, from: vertex)]
                case (false, false):
                    cornerPoints[outgoing.raw] = anyAtVertex
                        ? [slid(incoming, from: vertex), slid(outgoing, from: vertex)]
                        : [point("v\(vertex.raw)") { position(vertex) }]
                }
            }
        }

        /// Points from `from` to `to` (inclusive) along a quadratic Bezier with control `corner`.
        /// Keyed by the unordered endpoint pair so a strip and a vertex patch get the same points.
        func arc(_ from: Int, _ to: Int, corner: HalfEdgeTopology.VertexID) -> [Int] {
            guard segments > 1, from != to else {
                return [from, to]
            }
            let (low, high) = (min(from, to), max(from, to))
            let samples = (0...segments).map { step -> Int in
                if step == 0 { return low }
                if step == segments { return high }
                return point("a\(low)-\(high)-\(step)") {
                    let t = Float(step) / Float(segments)
                    let start = newPositions[low]
                    let end = newPositions[high]
                    return (1 - t) * (1 - t) * start + 2 * t * (1 - t) * position(corner) + t * t * end
                }
            }
            return from == low ? samples : samples.reversed()
        }

        var faces: [[Int]] = []
        // Shrunk original faces.
        for face in topology.faces where face.edge != nil {
            faces.append(topology.halfEdgeLoop(for: face.id).flatMap { cornerPoints[$0.raw]! })
        }
        // Edge strips: for a → b in F (twin b → a in G): F's a-side and b-side points, then G's.
        var stripDone = Set<Int>()
        for halfEdge in topology.halfEdges where isChamfered(halfEdge.id) && !stripDone.contains(halfEdge.id.raw) {
            let twin = halfEdge.twin!
            stripDone.formUnion([halfEdge.id.raw, twin.raw])
            let next = halfEdge.next!
            let twinNext = topology.halfEdges[twin.raw].next!
            let fA = cornerPoints[halfEdge.id.raw]!.last!
            let fB = cornerPoints[next.raw]!.first!
            let gB = cornerPoints[twin.raw]!.last!
            let gA = cornerPoints[twinNext.raw]!.first!
            let arcA = arc(fA, gA, corner: halfEdge.origin)
            let arcB = arc(fB, gB, corner: topology.halfEdges[next.raw].origin)
            for step in 0..<(arcA.count - 1) {
                faces.append([arcB[step], arcA[step], arcA[step + 1], arcB[step + 1]])
            }
        }
        // Vertex patches.
        for vertex in topology.vertices where topology.vertexRing(vertex.id).contains(where: isChamfered) {
            var loop: [Int] = []
            // Ring order crosses each face's incoming edge into the next face, so a face's
            // incoming-side point neighbors the next face's outgoing-side point: walk each reversed.
            // Crossing a chamfered edge into the next face follows that strip's arc.
            for outgoing in topology.vertexRing(vertex.id) {
                for index in cornerPoints[outgoing.raw]!.reversed() where loop.last != index {
                    loop.append(index)
                }
                let incoming = topology.halfEdges[outgoing.raw].prev!
                if isChamfered(incoming), let nextFaceCorner = topology.halfEdges[incoming.raw].twin {
                    let arcPoints = arc(loop.last!, cornerPoints[nextFaceCorner.raw]!.last!, corner: vertex.id)
                    loop += arcPoints.dropFirst().dropLast()
                }
            }
            if loop.count > 1, loop.first == loop.last {
                loop.removeLast()
            }
            guard loop.count >= 3 else {
                continue
            }
            // Wind the patch so it faces away from the solid (along the vertex's mean face normal).
            let outward = topology.vertexRing(vertex.id).reduce(SIMD3<Float>.zero) { $0 + faceNormal(topology.halfEdges[$1.raw].face!) }
            var newell = SIMD3<Float>.zero
            for index in loop.indices {
                newell += simd_cross(newPositions[loop[index]], newPositions[loop[(index + 1) % loop.count]])
            }
            faces.append(simd_dot(newell, outward) >= 0 ? loop : loop.reversed())
        }

        var result = Mesh(positions: newPositions, faces: faces)
        result.applyAttributes(attributes)
        return result
    }
}

private extension HalfEdgeTopology {
    /// Outgoing half-edges around a vertex of a closed manifold, in fan order.
    func vertexRing(_ vertex: VertexID) -> [HalfEdgeID] {
        guard let start = vertices[vertex.raw].edge else {
            return []
        }
        var ring: [HalfEdgeID] = []
        var current = start
        repeat {
            ring.append(current)
            guard let previous = halfEdges[current.raw].prev, let twin = halfEdges[previous.raw].twin else {
                break
            }
            current = twin
        } while current != start && ring.count <= halfEdges.count
        return ring
    }
}

/// The point `distance` inside both edges u→v and v→w, in the face plane.
private func offsetCorner(at v: SIMD3<Float>, from u: SIMD3<Float>, to w: SIMD3<Float>, normal: SIMD3<Float>, distance: Float) -> SIMD3<Float> {
    let inward1 = simd_normalize(simd_cross(normal, v - u))
    let inward2 = simd_normalize(simd_cross(normal, w - v))
    // Solve x·inward1 = d, x·inward2 = d with x = a·inward1 + b·inward2.
    let c = simd_dot(inward1, inward2)
    let determinant = 1 - c * c
    guard determinant > 1e-6 else {
        return v + inward1 * distance
    }
    let a = distance * (1 - c) / determinant
    return v + (inward1 + inward2) * a
}
