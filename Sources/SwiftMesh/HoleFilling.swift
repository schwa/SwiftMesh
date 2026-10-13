import simd

public extension Mesh {
    /// Close boundary loops (holes) with one new n-gon face each.
    ///
    /// Each new face is wound to pair with the hole's boundary edges, so a mesh whose only
    /// defects are holes becomes closed and consistently oriented. Non-planar holes still get
    /// a single face; triangulation handles them later by projection. Per-corner attributes
    /// on the new faces are copied from the neighboring corner at each vertex, and normals are
    /// set to the hole's flat normal. New faces join the submesh of a face beside the hole.
    ///
    /// - Parameter maxEdges: Skip holes with more edges than this, keeping intentional openings
    ///   (for example a hemisphere's rim) open. `nil` fills every hole.
    func fillingHoles(maxEdges: Int? = nil) -> Mesh {
        let loops = topology.boundaryLoops().filter { loop in maxEdges.map { loop.count <= $0 } ?? true }
        guard !loops.isEmpty else {
            return self
        }

        // The twin-less half-edge leaving each boundary vertex supplies the new corner's attributes.
        var boundaryCorner: [Int: HalfEdgeTopology.HalfEdgeID] = [:]
        for halfEdge in topology.halfEdges where halfEdge.twin == nil && halfEdge.next != nil {
            boundaryCorner[halfEdge.origin.raw] = boundaryCorner[halfEdge.origin.raw] ?? halfEdge.id
        }

        var definitions: [HalfEdgeTopology.FaceDefinition] = []
        var corners: [Int] = []
        var faceSources: [HalfEdgeTopology.FaceID?] = []
        for face in topology.faces {
            let order = topology.rebuildCornerOrder(for: face.id)
            guard !order.isEmpty else {
                continue
            }
            faceSources.append(face.id)
            definitions.append(.init(
                outer: topology.vertexLoop(for: face.id).map(\.raw),
                holes: topology.holeVertexLoops(for: face.id).map { $0.map(\.raw) }.filter { $0.count >= 3 }
            ))
            corners += order.map(\.raw)
        }

        var newFaceRanges: [(range: Range<Int>, normal: SIMD3<Float>)] = []
        for loop in loops {
            // Boundary loops run opposite to the face that would close them.
            let fill = Array(loop.reversed())
            let start = corners.count
            definitions.append(.init(outer: fill.map(\.raw)))
            corners += fill.map { boundaryCorner[$0.raw]!.raw }
            var newell = SIMD3<Float>.zero
            for index in fill.indices {
                newell += simd_cross(positions[fill[index].raw], positions[fill[(index + 1) % fill.count].raw])
            }
            let normal = simd_length(newell) > 0 ? simd_normalize(newell) : .zero
            faceSources.append(topology.halfEdges[boundaryCorner[loop[0].raw]!.raw].face)
            newFaceRanges.append((start..<corners.count, normal))
        }

        var result = Mesh(
            topology: HalfEdgeTopology(vertexCount: positions.count, faces: definitions),
            positions: positions,
            submeshes: submeshes(rebuiltFrom: faceSources)
        )

        var attributes = CornerAttributes(of: self).gathered(corners)
        if attributes.normals != nil {
            for fill in newFaceRanges {
                for corner in fill.range {
                    attributes.normals![corner] = fill.normal
                }
            }
        }
        attributes.apply(to: &result)
        return result
    }
}
