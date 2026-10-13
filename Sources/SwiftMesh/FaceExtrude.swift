import simd

public extension Mesh {
    /// Push a face outward along its normal and connect it to its old boundary with side walls.
    ///
    /// The face moves to new vertices offset by `distance` along ``faceNormal(_:)``.
    /// Each boundary edge (outer loop and holes) gets a quad wall. Per-corner attributes
    /// are copied from the face's corners; wall normals are set to the flat wall normal.
    /// Walls join the submesh of the extruded face. Use a negative distance to push inward.
    func extrudingFace(_ face: HalfEdgeTopology.FaceID, distance: Float) -> Mesh {
        guard topology.faces[face.raw].edge != nil else {
            return self
        }
        let offset = faceNormal(face) * distance
        let loops = [topology.halfEdgeLoop(for: face)] + topology.faces[face.raw].holeEdges.map { topology.collectHalfEdgeLoop(startEdge: $0) }

        var newPositions = positions
        var lifted: [Int: Int] = [:] // old vertex → new vertex
        for loop in loops {
            for halfEdge in loop {
                let vertex = topology.halfEdges[halfEdge.raw].origin.raw
                if lifted[vertex] == nil {
                    lifted[vertex] = newPositions.count
                    newPositions.append(positions[vertex] + offset)
                }
            }
        }

        var definitions: [HalfEdgeTopology.FaceDefinition] = []
        var corners: [Int] = []
        var faceSources: [HalfEdgeTopology.FaceID?] = []
        for oldFace in topology.faces {
            let order = topology.rebuildCornerOrder(for: oldFace.id)
            guard !order.isEmpty else {
                continue
            }
            faceSources.append(oldFace.id)
            let outer = topology.vertexLoop(for: oldFace.id).map(\.raw)
            let holes = topology.holeVertexLoops(for: oldFace.id).map { $0.map(\.raw) }.filter { $0.count >= 3 }
            if oldFace.id == face {
                definitions.append(.init(outer: outer.map { lifted[$0]! }, holes: holes.map { $0.map { lifted[$0]! } }))
            } else {
                definitions.append(.init(outer: outer, holes: holes))
            }
            corners += order.map(\.raw)
        }

        // Walls: for boundary edge a → b, quad (a, b, b', a'). Its a → b twins the neighbor's b → a; its b' → a' twins the top face's a' → b'.
        var wallNormals: [(range: Range<Int>, normal: SIMD3<Float>)] = []
        for loop in loops {
            for halfEdge in loop {
                let next = topology.halfEdges[halfEdge.raw].next!
                let a = topology.halfEdges[halfEdge.raw].origin.raw
                let b = topology.halfEdges[next.raw].origin.raw
                faceSources.append(face)
                definitions.append(.init(outer: [a, b, lifted[b]!, lifted[a]!]))
                let start = corners.count
                corners += [halfEdge.raw, next.raw, next.raw, halfEdge.raw]
                let normal = simd_cross(positions[b] - positions[a], offset)
                wallNormals.append((start..<corners.count, simd_length(normal) > 0 ? simd_normalize(normal) : .zero))
            }
        }

        var result = Mesh(
            topology: HalfEdgeTopology(vertexCount: newPositions.count, faces: definitions),
            positions: newPositions,
            submeshes: submeshes(rebuiltFrom: faceSources)
        )
        var attributes = CornerAttributes(of: self).gathered(corners)
        if attributes.normals != nil {
            for wall in wallNormals {
                for corner in wall.range {
                    attributes.normals![corner] = wall.normal
                }
            }
        }
        attributes.apply(to: &result)
        return result
    }
}
