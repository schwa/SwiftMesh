import simd

public extension Mesh {
    /// Merge adjacent coplanar faces into larger polygons.
    ///
    /// Faces whose normals are within `angleTolerance` radians and whose
    /// planes are within `distanceTolerance` are considered coplanar.
    /// Adjacent coplanar faces are grouped and replaced with a single polygon
    /// formed from their outer boundary.
    ///
    /// This is useful as a post-processing step after CSG operations,
    /// which tend to over-triangulate flat surfaces.
    func mergingCoplanarFaces(angleTolerance: Float = 1e-4, distanceTolerance: Float = 1e-4) -> Mesh {
        let positions = self.positions

        // Build face planes
        struct FacePlane {
            var normal: SIMD3<Float>
            var distance: Float
        }

        var facePlanes: [Int: FacePlane] = [:]
        for face in topology.faces {
            let n = faceNormal(face.id)
            let verts = topology.vertexLoop(for: face.id)
            guard !verts.isEmpty else { continue }
            let d = simd_dot(n, positions[verts[0].raw])
            facePlanes[face.id.raw] = FacePlane(normal: n, distance: d)
        }

        func areCoplanar(_ a: Int, _ b: Int) -> Bool {
            guard let pa = facePlanes[a], let pb = facePlanes[b] else { return false }
            let dot = simd_dot(pa.normal, pb.normal)
            guard dot >= cos(angleTolerance) else { return false }
            return abs(pa.distance - pb.distance) < distanceTolerance
        }

        // Build adjacency and find coplanar groups using union-find
        let faceCount = topology.faces.count
        var parent = Array(0..<faceCount)

        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }

        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }

        // For each interior edge, if the two faces are coplanar, union them
        for he in topology.halfEdges {
            guard let twinID = he.twin, he.id.raw < twinID.raw else { continue }
            guard let faceA = he.face, let faceB = topology.halfEdges[twinID.raw].face else { continue }
            guard faceA != faceB else { continue }
            if areCoplanar(faceA.raw, faceB.raw) {
                union(faceA.raw, faceB.raw)
            }
        }

        // Also check for coplanar faces sharing edges geometrically but without
        // twin linkage (can happen after CSG produces near-duplicate vertices).
        // Collect all boundary half-edges, then brute-force match nearby reverse edges.
        let edgeMatchTolerance: Float = 0.02

        struct BoundaryEdge {
            var heID: HalfEdgeTopology.HalfEdgeID
            var faceID: HalfEdgeTopology.FaceID
            var origin: SIMD3<Float>
            var dest: SIMD3<Float>
        }

        var boundaryEdgeList: [BoundaryEdge] = []
        for he in topology.halfEdges where he.twin == nil {
            guard let faceID = he.face, let next = he.next else { continue }
            boundaryEdgeList.append(BoundaryEdge(
                heID: he.id, faceID: faceID,
                origin: positions[he.origin.raw],
                dest: positions[topology.halfEdges[next.raw].origin.raw]
            ))
        }

        // Match boundary edges: edge A→B matches edge B'→A' if A≈B' and B≈A'
        for i in 0..<boundaryEdgeList.count {
            let ei = boundaryEdgeList[i]
            for j in (i + 1)..<boundaryEdgeList.count {
                let ej = boundaryEdgeList[j]
                guard ei.faceID != ej.faceID else { continue }
                let d = simd_distance(ei.origin, ej.dest) + simd_distance(ei.dest, ej.origin)
                if d < edgeMatchTolerance, areCoplanar(ei.faceID.raw, ej.faceID.raw) {
                    union(ei.faceID.raw, ej.faceID.raw)
                }
            }
        }

        // Group faces by their root
        var groups: [Int: [Int]] = [:]
        for i in 0..<faceCount {
            groups[find(i), default: []].append(i)
        }

        // For each group, either pass through unchanged (single face)
        // or find the outer boundary of the merged region
        // Per group: its plane normal and every boundary loop (outer and holes), before
        // collinear cleanup, which needs to know how many groups share each vertex.
        var groupLoops: [(normal: SIMD3<Float>, loops: [[Int]])] = []

        // Dictionary order is random; emit groups in order of their lowest face index.
        for group in groups.values.sorted(by: { $0[0] < $1[0] }) {
            if group.count == 1 {
                // Single face — keep as-is
                let faceID = HalfEdgeTopology.FaceID(raw: group[0])
                let verts = topology.vertexLoop(for: faceID)
                guard verts.count >= 3 else { continue }
                let holes = topology.holeVertexLoops(for: faceID).map { $0.map(\.raw) }.filter { $0.count >= 3 }
                groupLoops.append((faceNormal(faceID), [verts.map(\.raw)] + holes))
                continue
            }

            // Find boundary edges of this group: edges where one face is in the group
            // and the other is not (or is a true boundary edge).
            // An edge is interior if it has a twin in the group OR if there's a
            // geometrically-matching reverse edge from another face in the group.
            let groupSet = Set(group)

            // Collect all directed edges from this group with their positions
            struct GroupEdge {
                var faceIdx: Int
                var originIdx: Int
                var destIdx: Int
                var origin: SIMD3<Float>
                var dest: SIMD3<Float>
            }
            var groupEdges: [GroupEdge] = []
            for faceIdx in group {
                let faceID = HalfEdgeTopology.FaceID(raw: faceIdx)
                let heLoop = topology.halfEdgeLoop(for: faceID)
                for heID in heLoop {
                    let he = topology.halfEdges[heID.raw]
                    guard let next = he.next else { continue }
                    let destVID = topology.halfEdges[next.raw].origin
                    groupEdges.append(GroupEdge(
                        faceIdx: faceIdx,
                        originIdx: he.origin.raw,
                        destIdx: destVID.raw,
                        origin: positions[he.origin.raw],
                        dest: positions[destVID.raw]
                    ))
                }
            }

            var boundaryEdges: [(Int, Int)] = []

            for faceIdx in group {
                let faceID = HalfEdgeTopology.FaceID(raw: faceIdx)
                let heLoop = topology.halfEdgeLoop(for: faceID)
                for heID in heLoop {
                    let he = topology.halfEdges[heID.raw]
                    guard let next = he.next else { continue }
                    let origin = he.origin.raw
                    let dest = topology.halfEdges[next.raw].origin.raw

                    // Check twin linkage. A twin in another group makes this a real boundary;
                    // only twinless edges (unwelded input) fall back to geometric matching, since
                    // short exact edges near cuts would otherwise match unrelated neighbors.
                    if let twinID = he.twin {
                        let twinFace = topology.halfEdges[twinID.raw].face
                        if let tf = twinFace, groupSet.contains(tf.raw) {
                            continue // interior via twin
                        }
                        boundaryEdges.append((origin, dest))
                        continue
                    }

                    // Check geometric match: is there a reverse edge in this group?
                    let posO = positions[origin]
                    let posD = positions[dest]
                    var hasGeometricMatch = false
                    for ge in groupEdges where ge.faceIdx != faceIdx {
                        let d = simd_distance(ge.origin, posD) + simd_distance(ge.dest, posO)
                        if d < edgeMatchTolerance {
                            hasGeometricMatch = true
                            break
                        }
                    }
                    if hasGeometricMatch { continue }

                    boundaryEdges.append((origin, dest))
                }
            }

            // Chain boundary edges into an ordered loop
            guard !boundaryEdges.isEmpty else { continue }

            // Build adjacency: from vertex → next vertex
            // Several boundary edges can leave one vertex (holes touching the outline), so keep
            // a list per vertex and walk until every edge is used: one loop per boundary.
            var outgoing: [Int: [Int]] = [:]
            for (a, b) in boundaryEdges {
                outgoing[a, default: []].append(b)
            }
            var loops: [[Int]] = []
            for (firstStart, _) in boundaryEdges {
                guard outgoing[firstStart]?.isEmpty == false else {
                    continue
                }
                var loop: [Int] = []
                var current = firstStart
                var safety = boundaryEdges.count + 1
                repeat {
                    loop.append(current)
                    guard var targets = outgoing[current], !targets.isEmpty else {
                        break
                    }
                    let next = targets.removeFirst()
                    outgoing[current] = targets
                    current = next
                    safety -= 1
                } while current != firstStart && safety > 0
                if loop.count >= 3 {
                    loops.append(loop)
                }
            }
            guard !loops.isEmpty else { continue }
            groupLoops.append((faceNormal(HalfEdgeTopology.FaceID(raw: group[0])), loops))
        }

        // A collinear vertex can only be dropped if at most two groups use it: then no other face
        // keeps it, and a second group shares the same neighbors through it and drops it too.
        // With a third group it stays, or dropping it would leave a T-junction.
        var groupsPerVertex = [Int](repeating: 0, count: positions.count)
        for (_, loops) in groupLoops {
            for vertex in Set(loops.flatMap { $0 }) {
                groupsPerVertex[vertex] += 1
            }
        }
        var newFaces: [HalfEdgeTopology.FaceDefinition] = []
        for (normal, loops) in groupLoops {
            let cleaned = loops.map { loop in
                removeCollinearVertices(loop, positions: positions) { groupsPerVertex[$0] <= 2 }
            }.filter { $0.count >= 3 }
            // Loops wound with the face normal are outlines; the rest are holes.
            let outlines = cleaned.filter { loopArea(along: normal, $0, positions) > 0 }
            let holes = cleaned.filter { loopArea(along: normal, $0, positions) <= 0 }
            guard !outlines.isEmpty else { continue }
            if outlines.count == 1 {
                newFaces.append(.init(outer: outlines[0], holes: holes))
            } else {
                // Several outlines (a pinched region): give each hole to the outline containing it.
                for outline in outlines {
                    let mine = holes.filter { loopContains(outline, positions[$0[0]], normal: normal, positions) }
                    newFaces.append(.init(outer: outline, holes: mine))
                }
            }
        }

        // Compact positions
        var usedVertices = Set<Int>()
        for face in newFaces {
            usedVertices.formUnion(face.outer)
            for hole in face.holes { usedVertices.formUnion(hole) }
        }
        var remap = [Int](repeating: -1, count: positions.count)
        var compactPositions: [SIMD3<Float>] = []
        for idx in 0..<positions.count where usedVertices.contains(idx) {
            remap[idx] = compactPositions.count
            compactPositions.append(positions[idx])
        }
        let remappedFaces = newFaces.map { face in
            HalfEdgeTopology.FaceDefinition(outer: face.outer.map { remap[$0] }, holes: face.holes.map { $0.map { remap[$0] } })
        }

        return Mesh(positions: compactPositions, faces: remappedFaces)
    }
}

/// Signed area of a loop measured along `normal` (positive when wound counter-clockwise around it).
private func loopArea(along normal: SIMD3<Float>, _ loop: [Int], _ positions: [SIMD3<Float>]) -> Float {
    var sum = SIMD3<Float>.zero
    for index in loop.indices {
        sum += simd_cross(positions[loop[index]], positions[loop[(index + 1) % loop.count]])
    }
    return simd_dot(sum, normal) / 2
}

/// Whether `point` lies inside `loop`, tested in the plane perpendicular to `normal`.
private func loopContains(_ loop: [Int], _ point: SIMD3<Float>, normal: SIMD3<Float>, _ positions: [SIMD3<Float>]) -> Bool {
    let axis = abs(normal.x) > abs(normal.y) && abs(normal.x) > abs(normal.z) ? 0 : (abs(normal.y) > abs(normal.z) ? 1 : 2)
    func flat(_ p: SIMD3<Float>) -> SIMD2<Float> {
        axis == 0 ? SIMD2(p.y, p.z) : (axis == 1 ? SIMD2(p.z, p.x) : SIMD2(p.x, p.y))
    }
    let test = flat(point)
    var inside = false
    var previous = loop.count - 1
    for index in loop.indices {
        let a = flat(positions[loop[index]])
        let b = flat(positions[loop[previous]])
        if (a.y > test.y) != (b.y > test.y), test.x < (b.x - a.x) * (test.y - a.y) / (b.y - a.y) + a.x {
            inside.toggle()
        }
        previous = index
    }
    return inside
}

/// Remove vertices that lie on the straight line between their neighbors, if `canRemove` allows.
private func removeCollinearVertices(_ indices: [Int], positions: [SIMD3<Float>], tolerance: Float = 1e-4, canRemove: (Int) -> Bool = { _ in true }) -> [Int] {
    guard indices.count >= 3 else { return indices }
    var result: [Int] = []
    let n = indices.count
    for i in 0..<n {
        let prev = positions[indices[(i + n - 1) % n]]
        let curr = positions[indices[i]]
        let next = positions[indices[(i + 1) % n]]

        let edge1 = curr - prev
        let edge2 = next - curr
        let cross = simd_cross(edge1, edge2)
        let crossLen = simd_length(cross)
        let edgeLen = simd_length(edge1) * simd_length(edge2)
        if edgeLen > 0, crossLen / edgeLen < tolerance, canRemove(indices[i]) {
            continue
        }
        result.append(indices[i])
    }
    return result
}
