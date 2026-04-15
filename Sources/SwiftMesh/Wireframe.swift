import simd

// MARK: - Mesh Merging

public extension Mesh {
    /// Merge multiple meshes into a single mesh.
    ///
    /// Positions are concatenated, face indices are offset, and per-corner
    /// attributes are combined. Submeshes from all inputs are preserved.
    ///
    /// Attributes (normals, UVs, tangents, bitangents, colors) are included
    /// only if **all** input meshes provide them.
    static func merged(_ meshes: [Mesh]) -> Mesh {
        guard let first = meshes.first else {
            return Mesh(positions: [], faces: [] as [[Int]])
        }
        guard meshes.count > 1 else {
            return first
        }

        var allPositions: [SIMD3<Float>] = []
        var allFaceDefs: [HalfEdgeTopology.FaceDefinition] = []

        // Determine which per-corner attributes all meshes share
        let hasNormals = meshes.allSatisfy { $0.normals != nil }
        let hasTexCoords = meshes.allSatisfy { $0.textureCoordinates != nil }
        let hasTangents = meshes.allSatisfy { $0.tangents != nil }
        let hasBitangents = meshes.allSatisfy { $0.bitangents != nil }
        let hasColors = meshes.allSatisfy { $0.colors != nil }

        // We'll accumulate per-corner attributes in face order, then rebuild
        var allNormals: [SIMD3<Float>] = []
        var allTexCoords: [SIMD2<Float>] = []
        var allTangents: [SIMD3<Float>] = []
        var allBitangents: [SIMD3<Float>] = []
        var allColors: [SIMD4<Float>] = []

        for mesh in meshes {
            let vertexOffset = allPositions.count
            allPositions.append(contentsOf: mesh.positions)

            for face in mesh.topology.faces {
                let verts = mesh.topology.vertexLoop(for: face.id)
                let remapped = verts.map { $0.raw + vertexOffset }
                let holes = mesh.topology.holeVertexLoops(for: face.id).map { loop in
                    loop.map { $0.raw + vertexOffset }
                }

                allFaceDefs.append(.init(outer: remapped, holes: holes))

                // Collect per-corner attributes in face-loop order
                let heLoop = mesh.topology.halfEdgeLoop(for: face.id)
                for he in heLoop {
                    if hasNormals { allNormals.append(mesh.normals![he.raw]) }
                    if hasTexCoords { allTexCoords.append(mesh.textureCoordinates![he.raw]) }
                    if hasTangents { allTangents.append(mesh.tangents![he.raw]) }
                    if hasBitangents { allBitangents.append(mesh.bitangents![he.raw]) }
                    if hasColors { allColors.append(mesh.colors![he.raw]) }
                }
            }
        }

        let topo = HalfEdgeTopology(vertexCount: allPositions.count, faces: allFaceDefs)

        // Map accumulated per-corner attributes into the new topology's half-edge order.
        // Since we walked faces in the same order as the topology was built, face N in
        // allFaceDefs corresponds to face N in topo, and the loop order matches.
        var newNormals: [SIMD3<Float>]?
        var newTexCoords: [SIMD2<Float>]?
        var newTangents: [SIMD3<Float>]?
        var newBitangents: [SIMD3<Float>]?
        var newColors: [SIMD4<Float>]?

        if hasNormals { newNormals = [SIMD3<Float>](repeating: .zero, count: topo.halfEdges.count) }
        if hasTexCoords { newTexCoords = [SIMD2<Float>](repeating: .zero, count: topo.halfEdges.count) }
        if hasTangents { newTangents = [SIMD3<Float>](repeating: .zero, count: topo.halfEdges.count) }
        if hasBitangents { newBitangents = [SIMD3<Float>](repeating: .zero, count: topo.halfEdges.count) }
        if hasColors { newColors = [SIMD4<Float>](repeating: .zero, count: topo.halfEdges.count) }

        var cornerIdx = 0
        for faceIdx in 0..<topo.faces.count {
            let faceID = HalfEdgeTopology.FaceID(raw: faceIdx)
            let heLoop = topo.halfEdgeLoop(for: faceID)
            for he in heLoop {
                if hasNormals { newNormals![he.raw] = allNormals[cornerIdx] }
                if hasTexCoords { newTexCoords![he.raw] = allTexCoords[cornerIdx] }
                if hasTangents { newTangents![he.raw] = allTangents[cornerIdx] }
                if hasBitangents { newBitangents![he.raw] = allBitangents[cornerIdx] }
                if hasColors { newColors![he.raw] = allColors[cornerIdx] }
                cornerIdx += 1
            }
        }

        return Mesh(
            topology: topo,
            positions: allPositions,
            normals: newNormals,
            textureCoordinates: newTexCoords,
            tangents: newTangents,
            bitangents: newBitangents,
            colors: newColors
        )
    }
}

// MARK: - Wireframe Mesh

public extension Mesh {
    /// Generate a "phat wireframe" mesh: prisms extruded along each edge of the input mesh.
    ///
    /// Each unique undirected edge becomes an N-sided prism (tube) centered on
    /// that edge segment. The result is a solid mesh whose surface traces the
    /// wireframe of the original.
    ///
    /// - Parameters:
    ///   - radius: Half-thickness of each prism (distance from edge center to prism surface).
    ///   - sides: Number of sides for each prism cross-section. Use 4 for rectangular tubes,
    ///     higher values for cylindrical appearance.
    ///   - capped: Whether to add end caps to each prism. Defaults to `true`.
    ///   - attributes: Which attributes to compute on the result.
    /// - Returns: A new mesh composed of prisms along every edge.
    func wireframe(radius: Float = 0.01, sides: Int = 4, capped: Bool = true, attributes: MeshAttributes = .default) -> Mesh {
        let edges = topology.undirectedEdges()
        let clampedSides = max(3, sides)

        var prisms: [Mesh] = []
        prisms.reserveCapacity(edges.count)

        for (vertA, vertB) in edges {
            let posA = positions[vertA.raw]
            let posB = positions[vertB.raw]
            let prism = Mesh.edgePrism(from: posA, to: posB, radius: radius, sides: clampedSides, capped: capped)
            prisms.append(prism)
        }

        var result = Mesh.merged(prisms)
        if attributes.contains(.textureCoordinates) {
            result = result.withBoxUVs()
        }
        result.applyAttributes(attributes)
        return result
    }

    /// Generate a prism (tube) along a line segment between two points.
    ///
    /// The prism is an N-sided cylinder centered on the segment from `start` to `end`.
    ///
    /// - Parameters:
    ///   - start: One endpoint of the segment.
    ///   - end: The other endpoint of the segment.
    ///   - radius: Half-thickness (distance from center axis to surface).
    ///   - sides: Number of sides for the cross-section.
    ///   - capped: Whether to add end caps.
    /// - Returns: A mesh representing the prism.
    static func edgePrism(from start: SIMD3<Float>, to end: SIMD3<Float>, radius: Float, sides: Int, capped: Bool = true) -> Mesh {
        let direction = end - start
        let length = simd_length(direction)
        guard length > 1e-8 else {
            // Degenerate edge — return empty mesh
            return Mesh(positions: [], faces: [] as [[Int]])
        }

        let axis = direction / length

        // Build orthonormal frame around the edge axis
        let reference: SIMD3<Float>
        if abs(axis.y) < 0.9 {
            reference = SIMD3<Float>(0, 1, 0)
        } else {
            reference = SIMD3<Float>(1, 0, 0)
        }
        let tangent = simd_normalize(simd_cross(axis, reference))
        let bitangent = simd_cross(axis, tangent)

        // Generate ring vertices at start and end
        var positions: [SIMD3<Float>] = []
        var faces: [[Int]] = []

        // Start ring: indices 0..<sides
        for i in 0..<sides {
            let angle = 2 * Float.pi * Float(i) / Float(sides)
            let offset = tangent * (radius * cos(angle)) + bitangent * (radius * sin(angle))
            positions.append(start + offset)
        }

        // End ring: indices sides..<2*sides
        for i in 0..<sides {
            let angle = 2 * Float.pi * Float(i) / Float(sides)
            let offset = tangent * (radius * cos(angle)) + bitangent * (radius * sin(angle))
            positions.append(end + offset)
        }

        // Side quads connecting start ring to end ring
        for i in 0..<sides {
            let next = (i + 1) % sides
            // Winding: start[i], start[next], end[next], end[i]
            faces.append([i, next, sides + next, sides + i])
        }

        // End caps
        if capped {
            // Start cap (faces inward along -axis, so reverse winding)
            let startCap = (0..<sides).reversed().map(\.self)
            faces.append(startCap)

            // End cap (faces outward along +axis)
            let endCap = (0..<sides).map { $0 + sides }
            faces.append(endCap)
        }

        return Mesh(positions: positions, faces: faces)
    }
}

// MARK: - Border Mesh

public extension Mesh {
    /// Whether the border loop is inset (toward the face center) or outset
    /// (away from the face center).
    enum BorderDirection: Sendable {
        /// Shrink each face boundary inward toward the centroid.
        case inside
        /// Expand each face boundary outward away from the centroid.
        case outside
    }

    /// Generate a "border" mesh: a quad-strip frame around every face.
    ///
    /// For each face in the input mesh, an inset (or outset) copy of the
    /// boundary loop is created, and quad faces are emitted connecting
    /// the original boundary vertices to the offset boundary vertices.
    /// The result looks like a picture-frame or "phat wireframe" that
    /// follows the face topology instead of the edges.
    ///
    /// - Parameters:
    ///   - thickness: How far to offset the inner/outer loop from the
    ///     original boundary, measured along the face plane.
    ///   - direction: Whether to inset or outset the loop.
    ///   - triangulate: If `true`, each quad in the border strip is split
    ///     into two triangles (simple fan, no earcut needed).
    ///   - attributes: Which derived attributes to compute on the result.
    /// - Returns: A new mesh composed of border strips around every face.
    func border(
        thickness: Float = 0.02,
        direction: BorderDirection = .inside,
        triangulate: Bool = false,
        attributes: MeshAttributes = .default
    ) -> Mesh {
        var allPositions: [SIMD3<Float>] = []
        var allFaces: [[Int]] = []

        for face in topology.faces {
            let vertexIDs = topology.vertexLoop(for: face.id)
            guard vertexIDs.count >= 3 else { continue }

            let facePositions = vertexIDs.map { positions[$0.raw] }
            let centroid = facePositions.reduce(.zero, +) / Float(facePositions.count)
            let faceNorm = faceNormal(face.id)
            let count = facePositions.count

            // Compute offset positions by moving each vertex toward/away from
            // the centroid along the face plane.
            var offsetPositions: [SIMD3<Float>] = []
            offsetPositions.reserveCapacity(count)

            for i in 0..<count {
                let pos = facePositions[i]
                // Direction from centroid to vertex, projected onto the face plane
                var toVertex = pos - centroid
                // Remove the component along the face normal so we stay on-plane
                toVertex -= faceNorm * simd_dot(toVertex, faceNorm)
                let len = simd_length(toVertex)
                guard len > 1e-8 else {
                    // Degenerate — vertex is at the centroid; just keep it
                    offsetPositions.append(pos)
                    continue
                }
                let dir = toVertex / len
                switch direction {
                case .inside:
                    offsetPositions.append(pos - dir * thickness)
                case .outside:
                    offsetPositions.append(pos + dir * thickness)
                }
            }

            // Emit geometry: quad strip between original and offset loops.
            // Original loop vertices: baseIndex ..< baseIndex + count
            // Offset loop vertices:   baseIndex + count ..< baseIndex + 2*count
            let baseIndex = allPositions.count
            allPositions.append(contentsOf: facePositions)
            allPositions.append(contentsOf: offsetPositions)

            for i in 0..<count {
                let next = (i + 1) % count
                // Quad: outer[i], outer[next], inner[next], inner[i]
                let outerI: Int
                let outerNext: Int
                let innerI: Int
                let innerNext: Int

                switch direction {
                case .inside:
                    // Original = outer, offset = inner
                    outerI = baseIndex + i
                    outerNext = baseIndex + next
                    innerI = baseIndex + count + i
                    innerNext = baseIndex + count + next
                case .outside:
                    // Offset = outer, original = inner
                    outerI = baseIndex + count + i
                    outerNext = baseIndex + count + next
                    innerI = baseIndex + i
                    innerNext = baseIndex + next
                }

                if triangulate {
                    allFaces.append([outerI, outerNext, innerNext])
                    allFaces.append([outerI, innerNext, innerI])
                } else {
                    allFaces.append([outerI, outerNext, innerNext, innerI])
                }
            }
        }

        var result = Mesh(positions: allPositions, faces: allFaces)
        if attributes.contains(.textureCoordinates) {
            result = result.withBoxUVs()
        }
        result.applyAttributes(attributes)
        return result
    }
}
