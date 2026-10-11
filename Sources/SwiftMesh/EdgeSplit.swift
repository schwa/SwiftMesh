import simd

public extension Mesh {
    /// Insert a vertex on an edge and split the adjacent triangles.
    ///
    /// The new vertex is placed at `origin + t * (destination - origin)` of `halfEdge`.
    /// Each adjacent triangle is split in two by a new edge from the new vertex to the
    /// opposite corner, so an interior edge between two triangles yields four faces.
    /// Non-triangle faces gain the vertex but are not split. Per-corner attributes are
    /// interpolated at the new vertex. New faces join the submesh of the face they came from.
    ///
    /// - Returns: The new vertex, or `nil` if `halfEdge` is tombstoned.
    @discardableResult
    mutating func splitEdge(_ halfEdge: HalfEdgeTopology.HalfEdgeID, at t: Float = 0.5) -> HalfEdgeTopology.VertexID? {
        guard topology.halfEdges[halfEdge.raw].next != nil, let destination = topology.destViaNext(of: halfEdge) else {
            return nil
        }
        let origin = topology.halfEdges[halfEdge.raw].origin
        let twin = topology.halfEdges[halfEdge.raw].twin

        let middle = HalfEdgeTopology.VertexID(raw: topology.vertices.count)
        topology.vertices.append(.init(id: middle, edge: nil))
        positions.append(simd_mix(positions[origin.raw], positions[destination.raw], SIMD3(repeating: t)))

        // Split each directed half: `half` keeps its origin and now ends at `middle`; a new half-edge continues to the old end.
        let first = splitHalf(halfEdge, at: middle, t: t)
        var second: HalfEdgeTopology.HalfEdgeID?
        if let twin {
            second = splitHalf(twin, at: middle, t: 1 - t)
            // origin→middle pairs with middle→origin, middle→destination with destination→middle.
            link(halfEdge, second!)
            link(first, twin)
        }
        topology.vertices[middle.raw].edge = first

        triangulateFan(at: first)
        if let second {
            triangulateFan(at: second)
        }
        return middle
    }
}

private extension Mesh {
    /// Split `half` (origin X → Y) into X → `middle` (the existing id) and `middle` → Y (returned).
    mutating func splitHalf(_ half: HalfEdgeTopology.HalfEdgeID, at middle: HalfEdgeTopology.VertexID, t: Float) -> HalfEdgeTopology.HalfEdgeID {
        let old = topology.halfEdges[half.raw]
        let newID = HalfEdgeTopology.HalfEdgeID(raw: topology.halfEdges.count)
        topology.halfEdges.append(.init(id: newID, origin: middle, twin: nil, next: old.next, prev: half, face: old.face))
        topology.halfEdges[old.next!.raw].prev = newID
        topology.halfEdges[half.raw].next = newID
        topology.halfEdges[half.raw].twin = nil
        // Corner at `middle` interpolates the corners at this half's origin and at the following corner (old end).
        appendCorner(interpolating: half.raw, old.next!.raw, t: t)
        return newID
    }

    mutating func link(_ a: HalfEdgeTopology.HalfEdgeID, _ b: HalfEdgeTopology.HalfEdgeID) {
        topology.halfEdges[a.raw].twin = b
        topology.halfEdges[b.raw].twin = a
    }

    /// If the face containing `fromMiddle` (middle → Y) is now a quad `prev(X→middle), fromMiddle, Y→Z, Z→X`,
    /// split it along middle–Z into (X, middle, Z) and (middle, Y, Z).
    mutating func triangulateFan(at fromMiddle: HalfEdgeTopology.HalfEdgeID) {
        guard let face = topology.halfEdges[fromMiddle.raw].face else {
            return
        }
        let toMiddle = topology.halfEdges[fromMiddle.raw].prev! // X → middle
        let yToZ = topology.halfEdges[fromMiddle.raw].next! // Y → Z
        let zToX = topology.halfEdges[yToZ.raw].next! // Z → X
        guard topology.halfEdges[zToX.raw].next == toMiddle else {
            return // was not a triangle
        }
        let middle = topology.halfEdges[fromMiddle.raw].origin
        let z = topology.halfEdges[zToX.raw].origin

        let newFace = HalfEdgeTopology.FaceID(raw: topology.faces.count)
        let middleToZ = HalfEdgeTopology.HalfEdgeID(raw: topology.halfEdges.count)
        let zToMiddle = HalfEdgeTopology.HalfEdgeID(raw: topology.halfEdges.count + 1)

        // Face `face`: X → middle → Z → X
        topology.halfEdges.append(.init(id: middleToZ, origin: middle, twin: zToMiddle, next: zToX, prev: toMiddle, face: face))
        appendCorner(copying: fromMiddle.raw)
        // Face `newFace`: middle → Y → Z → middle
        topology.halfEdges.append(.init(id: zToMiddle, origin: z, twin: middleToZ, next: fromMiddle, prev: yToZ, face: newFace))
        appendCorner(copying: zToX.raw)

        topology.halfEdges[toMiddle.raw].next = middleToZ
        topology.halfEdges[zToX.raw].prev = middleToZ
        topology.halfEdges[fromMiddle.raw].prev = zToMiddle
        topology.halfEdges[yToZ.raw].next = zToMiddle
        topology.halfEdges[fromMiddle.raw].face = newFace
        topology.halfEdges[yToZ.raw].face = newFace

        topology.faces[face.raw].edge = toMiddle
        topology.faces.append(.init(id: newFace, edge: fromMiddle))
        if let submeshIndex = submeshes.firstIndex(where: { $0.faces.contains(face) }) {
            submeshes[submeshIndex].faces.append(newFace)
        }
    }

    mutating func appendCorner(interpolating a: Int, _ b: Int, t: Float) {
        func mix<T: SIMD>(_ values: inout [T]?) where T.Scalar == Float {
            guard values != nil else {
                return
            }
            let from = values![a]
            let to = values![b]
            values!.append(from + (to - from) * t)
        }
        mix(&normals)
        mix(&textureCoordinates)
        mix(&tangents)
        mix(&bitangents)
        mix(&colors)
        if let last = normals?.last, simd_length(last) > 0 {
            normals![normals!.count - 1] = simd_normalize(last)
        }
    }

    mutating func appendCorner(copying corner: Int) {
        func copy<T>(_ values: inout [T]?) {
            if values != nil {
                values!.append(values![corner])
            }
        }
        copy(&normals)
        copy(&textureCoordinates)
        copy(&tangents)
        copy(&bitangents)
        copy(&colors)
    }
}
