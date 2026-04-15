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

        // Group faces by their root
        var groups: [Int: [Int]] = [:]
        for i in 0..<faceCount {
            groups[find(i), default: []].append(i)
        }

        // For each group, either pass through unchanged (single face)
        // or find the outer boundary of the merged region
        var newFaces: [[Int]] = []

        for (_, group) in groups {
            if group.count == 1 {
                // Single face — keep as-is
                let verts = topology.vertexLoop(for: HalfEdgeTopology.FaceID(raw: group[0]))
                guard verts.count >= 3 else { continue }
                newFaces.append(verts.map(\.raw))
                continue
            }

            // Find boundary edges of this group: edges where one face is in the group
            // and the other is not (or is a boundary edge with no twin)
            let groupSet = Set(group)
            var boundaryEdges: [(Int, Int)] = [] // directed edges (origin, dest)

            for faceIdx in group {
                let faceID = HalfEdgeTopology.FaceID(raw: faceIdx)
                let heLoop = topology.halfEdgeLoop(for: faceID)
                for heID in heLoop {
                    let he = topology.halfEdges[heID.raw]
                    let origin = he.origin.raw
                    let dest: Int
                    if let next = he.next {
                        dest = topology.halfEdges[next.raw].origin.raw
                    } else {
                        continue
                    }

                    let isBoundary: Bool
                    if let twinID = he.twin {
                        let twinFace = topology.halfEdges[twinID.raw].face
                        isBoundary = twinFace == nil || !groupSet.contains(twinFace!.raw)
                    } else {
                        isBoundary = true
                    }

                    if isBoundary {
                        boundaryEdges.append((origin, dest))
                    }
                }
            }

            // Chain boundary edges into an ordered loop
            guard !boundaryEdges.isEmpty else { continue }

            // Build adjacency: from vertex → next vertex
            var nextVertex: [Int: Int] = [:]
            for (a, b) in boundaryEdges {
                nextVertex[a] = b
            }

            // Walk the loop
            let start = boundaryEdges[0].0
            var loop: [Int] = []
            var current = start
            var safety = nextVertex.count + 1
            repeat {
                loop.append(current)
                guard let next = nextVertex[current] else { break }
                current = next
                safety -= 1
            } while current != start && safety > 0

            guard loop.count >= 3 else { continue }

            // Remove collinear vertices
            let cleaned = removeCollinearVertices(loop, positions: positions)
            guard cleaned.count >= 3 else { continue }
            newFaces.append(cleaned)
        }

        // Compact positions
        var usedVertices = Set<Int>()
        for face in newFaces {
            for idx in face { usedVertices.insert(idx) }
        }
        var remap = [Int](repeating: -1, count: positions.count)
        var compactPositions: [SIMD3<Float>] = []
        for idx in 0..<positions.count where usedVertices.contains(idx) {
            remap[idx] = compactPositions.count
            compactPositions.append(positions[idx])
        }
        let remappedFaces = newFaces.map { $0.map { remap[$0] } }

        return Mesh(positions: compactPositions, faces: remappedFaces)
    }
}

/// Remove vertices that lie on the straight line between their neighbors.
private func removeCollinearVertices(_ indices: [Int], positions: [SIMD3<Float>], tolerance: Float = 1e-4) -> [Int] {
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
        if edgeLen > 0 && crossLen / edgeLen < tolerance {
            continue
        }
        result.append(indices[i])
    }
    return result
}
