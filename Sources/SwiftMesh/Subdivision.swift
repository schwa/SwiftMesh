import simd

// MARK: - Topology helpers for subdivision

extension HalfEdgeTopology {
    /// Returns all half-edges originating from a vertex by walking around it via twins.
    ///
    /// For interior vertices this returns a complete fan. For boundary vertices
    /// the result may be incomplete if the walk cannot close the loop.
    func outgoingHalfEdges(from vertex: VertexID) -> [HalfEdgeID] {
        guard let startEdge = vertices[vertex.raw].edge else {
            return []
        }
        var result: [HalfEdgeID] = [startEdge]
        var current = startEdge

        // Walk around vertex: prev of current → twin gives next outgoing edge
        while true {
            guard let prev = halfEdges[current.raw].prev else {
                break
            }
            guard let twin = halfEdges[prev.raw].twin else {
                break
            }
            if twin == startEdge {
                break
            }
            result.append(twin)
            current = twin
        }
        return result
    }

    /// Whether a vertex is on the mesh boundary (has an outgoing edge with no twin).
    func isBoundaryVertex(_ vertex: VertexID) -> Bool {
        let outgoing = outgoingHalfEdges(from: vertex)
        return outgoing.contains { halfEdges[$0.raw].twin == nil }
            || outgoing.isEmpty
    }

    /// Whether a half-edge is on the mesh boundary (has no twin).
    func isBoundaryEdge(_ edge: HalfEdgeID) -> Bool {
        halfEdges[edge.raw].twin == nil
    }

    /// Returns the neighbor vertex IDs around a vertex (one-ring).
    func oneRing(of vertex: VertexID) -> [VertexID] {
        outgoingHalfEdges(from: vertex).compactMap { destViaNext(of: $0) }
    }
}

// MARK: - Loop Subdivision

public extension Mesh {
    /// Applies Loop subdivision to a triangle mesh.
    ///
    /// Each triangle is split into four by inserting edge midpoints and
    /// repositioning original vertices using Loop's weights. The input mesh
    /// must consist entirely of triangles.
    ///
    /// Per-corner attributes (normals, UVs, tangents, colors) and submeshes
    /// are not preserved. Call attribute-generation methods on the result
    /// if needed.
    ///
    /// - Parameter iterations: Number of subdivision passes. Each pass
    ///   quadruples the triangle count.
    /// - Returns: A new subdivided mesh.
    func loopSubdivided(iterations: Int = 1) -> Mesh {
        var mesh = self
        for _ in 0..<iterations {
            mesh = mesh.loopSubdivideOnce()
        }
        return mesh
    }

    private func loopSubdivideOnce() -> Mesh {
        let topo = topology

        // Build edge key → edge point index mapping.
        // Edge key: sorted (min, max) vertex pair.
        var edgePointIndex: [Int64: Int] = [:]
        var newPositions = positions // start with original positions (will be updated)

        // For each undirected edge, compute the edge point.
        for he in topo.halfEdges {
            let originID = he.origin
            guard let destID = topo.destViaNext(of: he.id) else {
                continue
            }
            let key = edgeKey(originID.raw, destID.raw)
            if edgePointIndex[key] != nil {
                continue
            }

            let p0 = positions[originID.raw]
            let p1 = positions[destID.raw]

            let edgePoint: SIMD3<Float>
            if let twinID = he.twin,
               let faceA = he.face,
               let faceB = topo.halfEdges[twinID.raw].face {
                // Interior edge: 3/8 * (p0 + p1) + 1/8 * (p2 + p3)
                // where p2, p3 are the opposite vertices of the two adjacent triangles.
                let opposite0 = oppositeVertex(halfEdge: he.id, in: faceA)
                let opposite1 = oppositeVertex(halfEdge: twinID, in: faceB)
                let p2 = positions[opposite0.raw]
                let p3 = positions[opposite1.raw]
                edgePoint = (p0 + p1) * (3.0 / 8.0) + (p2 + p3) * (1.0 / 8.0)
            } else {
                // Boundary edge: simple midpoint
                edgePoint = (p0 + p1) * 0.5
            }

            edgePointIndex[key] = newPositions.count
            newPositions.append(edgePoint)
        }

        // Update original vertex positions using Loop's vertex rule.
        var updatedPositions = [SIMD3<Float>](repeating: .zero, count: positions.count)
        for vertex in topo.vertices {
            let neighbors = topo.oneRing(of: vertex.id)
            let n = neighbors.count

            if topo.isBoundaryVertex(vertex.id) {
                // Boundary vertex: 3/4 * v + 1/8 * (b0 + b1)
                // where b0, b1 are the two boundary neighbors.
                let boundaryNeighbors = boundaryNeighborVertices(of: vertex.id)
                if boundaryNeighbors.count == 2 {
                    updatedPositions[vertex.id.raw] = positions[vertex.id.raw] * (3.0 / 4.0)
                        + (positions[boundaryNeighbors[0].raw] + positions[boundaryNeighbors[1].raw]) * (1.0 / 8.0)
                } else {
                    updatedPositions[vertex.id.raw] = positions[vertex.id.raw]
                }
            } else if n > 0 {
                // Interior vertex: (1 - n*beta) * v + beta * sum(neighbors)
                let beta = loopBeta(valence: n)
                let neighborSum = neighbors.reduce(SIMD3<Float>.zero) { $0 + positions[$1.raw] }
                updatedPositions[vertex.id.raw] = positions[vertex.id.raw] * (1.0 - Float(n) * beta) + neighborSum * beta
            } else {
                updatedPositions[vertex.id.raw] = positions[vertex.id.raw]
            }
        }

        // Replace original positions with updated ones.
        for i in 0..<positions.count {
            newPositions[i] = updatedPositions[i]
        }

        // Build new faces: each triangle → 4 triangles.
        var newFaces: [[Int]] = []
        for face in topo.faces {
            let verts = topo.vertexLoop(for: face.id)
            guard verts.count == 3 else {
                continue
            }
            let v0 = verts[0].raw
            let v1 = verts[1].raw
            let v2 = verts[2].raw

            let e01 = edgePointIndex[edgeKey(v0, v1)]!
            let e12 = edgePointIndex[edgeKey(v1, v2)]!
            let e20 = edgePointIndex[edgeKey(v2, v0)]!

            // Four sub-triangles
            newFaces.append([v0, e01, e20])
            newFaces.append([v1, e12, e01])
            newFaces.append([v2, e20, e12])
            newFaces.append([e01, e12, e20])
        }

        return Mesh(positions: newPositions, faces: newFaces)
    }

    /// Loop's beta weight for a vertex of given valence.
    private func loopBeta(valence n: Int) -> Float {
        if n == 3 {
            return 3.0 / 16.0
        }
        let nf = Float(n)
        let center = 3.0 / 8.0 + cos(2.0 * .pi / nf) / 4.0
        return (1.0 / nf) * (5.0 / 8.0 - center * center)
    }

    /// Find the vertex in a face that is opposite to the given half-edge's endpoints.
    private func oppositeVertex(halfEdge: HalfEdgeTopology.HalfEdgeID, in face: HalfEdgeTopology.FaceID) -> HalfEdgeTopology.VertexID {
        let origin = topology.halfEdges[halfEdge.raw].origin
        let dest = topology.destViaNext(of: halfEdge)
        let verts = topology.vertexLoop(for: face)
        return verts.first { $0 != origin && $0 != dest } ?? origin
    }
}

// MARK: - Catmull-Clark Subdivision

public extension Mesh {
    /// Applies Catmull-Clark subdivision to a mesh.
    ///
    /// Each face is split by inserting a face point at its centroid and edge
    /// points at edge midpoints (adjusted by neighboring face points), then
    /// connecting them to form quads. Works on meshes with any polygon type
    /// (triangles, quads, n-gons) — the output is always quads.
    ///
    /// Per-corner attributes (normals, UVs, tangents, colors) and submeshes
    /// are not preserved. Call attribute-generation methods on the result
    /// if needed.
    ///
    /// - Parameter iterations: Number of subdivision passes. Each pass
    ///   roughly quadruples the face count.
    /// - Returns: A new subdivided mesh.
    func catmullClarkSubdivided(iterations: Int = 1) -> Mesh {
        var mesh = self
        for _ in 0..<iterations {
            mesh = mesh.catmullClarkSubdivideOnce()
        }
        return mesh
    }

    private func catmullClarkSubdivideOnce() -> Mesh {
        let topo = topology

        // 1. Compute face points (centroid of each face).
        var facePoints = [SIMD3<Float>](repeating: .zero, count: topo.faces.count)
        for face in topo.faces {
            facePoints[face.id.raw] = faceCentroid(face.id)
        }

        // 2. Compute edge points.
        // Interior edge: average of edge midpoint and average of adjacent face points.
        // Boundary edge: simple midpoint.
        var edgePointIndex: [Int64: Int] = [:]
        var newPositions = positions

        // Add face points to the position array.
        var facePointIndex = [Int](repeating: 0, count: topo.faces.count)
        for face in topo.faces {
            facePointIndex[face.id.raw] = newPositions.count
            newPositions.append(facePoints[face.id.raw])
        }

        // Compute edge points.
        for he in topo.halfEdges {
            let originID = he.origin
            guard let destID = topo.destViaNext(of: he.id) else {
                continue
            }
            let key = edgeKey(originID.raw, destID.raw)
            if edgePointIndex[key] != nil {
                continue
            }

            let p0 = positions[originID.raw]
            let p1 = positions[destID.raw]

            let edgePoint: SIMD3<Float>
            if let twinID = he.twin,
               let faceA = he.face,
               let faceB = topo.halfEdges[twinID.raw].face {
                // Interior: average of edge midpoint and the two face points
                let midpoint = (p0 + p1) * 0.5
                let faceMid = (facePoints[faceA.raw] + facePoints[faceB.raw]) * 0.5
                edgePoint = (midpoint + faceMid) * 0.5
            } else {
                // Boundary: simple midpoint
                edgePoint = (p0 + p1) * 0.5
            }

            edgePointIndex[key] = newPositions.count
            newPositions.append(edgePoint)
        }

        // 3. Update original vertex positions.
        // Interior vertex: (F + 2R + (n-3)P) / n
        //   F = average of face points for faces touching vertex
        //   R = average of edge midpoints for edges touching vertex
        //   P = original position
        //   n = valence
        // Boundary vertex: (1/8)b0 + (3/4)P + (1/8)b1
        var updatedPositions = [SIMD3<Float>](repeating: .zero, count: positions.count)
        for vertex in topo.vertices {
            if topo.isBoundaryVertex(vertex.id) {
                let boundaryNeighbors = boundaryNeighborVertices(of: vertex.id)
                if boundaryNeighbors.count == 2 {
                    updatedPositions[vertex.id.raw] = positions[vertex.id.raw] * (3.0 / 4.0)
                        + (positions[boundaryNeighbors[0].raw] + positions[boundaryNeighbors[1].raw]) * (1.0 / 8.0)
                } else {
                    updatedPositions[vertex.id.raw] = positions[vertex.id.raw]
                }
            } else {
                let outgoing = topo.outgoingHalfEdges(from: vertex.id)
                let n = outgoing.count
                guard n > 0 else {
                    updatedPositions[vertex.id.raw] = positions[vertex.id.raw]
                    continue
                }

                // F: average of adjacent face points
                var fAvg = SIMD3<Float>.zero
                var fCount = 0
                for heID in outgoing {
                    if let faceID = topo.halfEdges[heID.raw].face {
                        fAvg += facePoints[faceID.raw]
                        fCount += 1
                    }
                }
                if fCount > 0 {
                    fAvg /= Float(fCount)
                }

                // R: average of edge midpoints
                var rAvg = SIMD3<Float>.zero
                var rCount = 0
                for heID in outgoing {
                    if let dest = topo.destViaNext(of: heID) {
                        rAvg += (positions[vertex.id.raw] + positions[dest.raw]) * 0.5
                        rCount += 1
                    }
                }
                if rCount > 0 {
                    rAvg /= Float(rCount)
                }

                let nf = Float(n)
                updatedPositions[vertex.id.raw] = (fAvg + 2.0 * rAvg + (nf - 3.0) * positions[vertex.id.raw]) / nf
            }
        }

        // Apply updated positions.
        for i in 0..<positions.count {
            newPositions[i] = updatedPositions[i]
        }

        // 4. Build new faces: each original face → one quad per edge.
        // For each face with n edges, create n quads:
        //   [vertex_i, edgePoint(i, i+1), facePoint, edgePoint(i-1, i)]
        var newFaces: [[Int]] = []
        for face in topo.faces {
            let verts = topo.vertexLoop(for: face.id)
            let n = verts.count
            let fp = facePointIndex[face.id.raw]

            for i in 0..<n {
                let iPrev = (i + n - 1) % n
                let vi = verts[i].raw
                let ep1 = edgePointIndex[edgeKey(verts[i].raw, verts[(i + 1) % n].raw)]!
                let ep0 = edgePointIndex[edgeKey(verts[iPrev].raw, verts[i].raw)]!
                newFaces.append([vi, ep1, fp, ep0])
            }
        }

        return Mesh(positions: newPositions, faces: newFaces)
    }
}

// MARK: - Shared helpers

extension Mesh {
    /// Find boundary neighbor vertices (vertices connected by boundary edges).
    fileprivate func boundaryNeighborVertices(of vertex: HalfEdgeTopology.VertexID) -> [HalfEdgeTopology.VertexID] {
        let outgoing = topology.outgoingHalfEdges(from: vertex)
        var result: [HalfEdgeTopology.VertexID] = []
        for heID in outgoing {
            if topology.isBoundaryEdge(heID) {
                if let dest = topology.destViaNext(of: heID) {
                    result.append(dest)
                }
            }
        }
        for he in topology.halfEdges where topology.isBoundaryEdge(he.id) {
            if topology.destViaNext(of: he.id) == vertex, !result.contains(he.origin) {
                result.append(he.origin)
            }
        }
        return result
    }
}

// MARK: - Edge key helper

/// Canonical key for an undirected edge between two vertex indices.
private func edgeKey(_ a: Int, _ b: Int) -> Int64 {
    let lo = min(a, b)
    let hi = max(a, b)
    return Int64(lo) << 32 | Int64(hi)
}
