import simd

// Diagnostics ignore tombstoned elements (faces with no edge, half-edges with no next).

public extension HalfEdgeTopology {
    private var liveHalfEdges: [HalfEdge] {
        halfEdges.filter { $0.next != nil }
    }

    private var liveFaceIDs: [FaceID] {
        faces.filter { $0.edge != nil }.map(\.id)
    }

    /// Vertices that no live half-edge originates from.
    var hasOrphanedVertices: Bool {
        var used = [Bool](repeating: false, count: vertices.count)
        for halfEdge in liveHalfEdges {
            used[halfEdge.origin.raw] = true
        }
        return used.contains(false)
    }

    /// Alias for ``hasOrphanedVertices``.
    var hasZeroValenceVertices: Bool { hasOrphanedVertices }

    /// Live half-edges with no face, or whose twin has no face.
    var hasDanglingEdges: Bool {
        liveHalfEdges.contains { halfEdge in
            halfEdge.face == nil || halfEdge.twin.map { halfEdges[$0.raw].face == nil } == true
        }
    }

    /// Some half-edge's twin does not point back to it.
    var hasNonConsistentTwins: Bool {
        liveHalfEdges.contains { halfEdge in
            guard let twin = halfEdge.twin else {
                return false
            }
            return twin.raw >= halfEdges.count || halfEdges[twin.raw].twin != halfEdge.id
        }
    }

    /// Some half-edge's next/prev links are not mutual.
    var hasNonConsistentNextPrev: Bool {
        liveHalfEdges.contains { halfEdge in
            guard let next = halfEdge.next, let prev = halfEdge.prev else {
                return true
            }
            return halfEdges[next.raw].prev != halfEdge.id || halfEdges[prev.raw].next != halfEdge.id
        }
    }

    /// Number of boundary loops. Zero means watertight.
    var boundaryLoopCount: Int {
        boundaryLoops().count
    }

    /// Number of distinct neighbor vertices per vertex, indexed by `VertexID.raw`.
    var valences: [Int] {
        var neighbors = [Set<Int>](repeating: [], count: vertices.count)
        for halfEdge in liveHalfEdges {
            guard let destination = destViaNext(of: halfEdge.id) else {
                continue
            }
            neighbors[halfEdge.origin.raw].insert(destination.raw)
            neighbors[destination.raw].insert(halfEdge.origin.raw)
        }
        return neighbors.map(\.count)
    }

    /// Map of valence → number of vertices with that valence.
    func valenceHistogram() -> [Int: Int] {
        valences.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    func hasHighValenceVertices(threshold: Int) -> Bool {
        valences.contains { $0 > threshold }
    }

    /// Two live faces use the same set of vertices.
    var hasDuplicateFaces: Bool {
        var seen = Set<[Int]>()
        for face in liveFaceIDs {
            let key = vertexLoop(for: face).map(\.raw).sorted()
            if !seen.insert(key).inserted {
                return true
            }
        }
        return false
    }

    /// More than two half-edges connect the same pair of vertices, or two share a direction.
    var hasDuplicateEdges: Bool {
        var directed = Set<[Int]>()
        var undirected: [[Int]: Int] = [:]
        for halfEdge in liveHalfEdges {
            guard let destination = destViaNext(of: halfEdge.id) else {
                continue
            }
            let origin = halfEdge.origin.raw
            if !directed.insert([origin, destination.raw]).inserted {
                return true
            }
            let key = [min(origin, destination.raw), max(origin, destination.raw)]
            undirected[key, default: 0] += 1
            if undirected[key]! > 2 {
                return true
            }
        }
        return false
    }
}

public extension Mesh {
    /// Area of a face's outer boundary (Newell's method).
    func faceArea(_ face: HalfEdgeTopology.FaceID) -> Float {
        let points = facePositions(face)
        var sum = SIMD3<Float>.zero
        for index in points.indices {
            sum += simd_cross(points[index], points[(index + 1) % points.count])
        }
        return simd_length(sum) / 2
    }

    /// Live faces whose area is at most `tolerance`.
    func hasZeroAreaFaces(tolerance: Float = 1e-12) -> Bool {
        topology.faces.contains { $0.edge != nil && faceArea($0.id) <= tolerance }
    }

    /// Live faces with a vertex farther than `tolerance` from the face plane.
    func hasNonPlanarFaces(tolerance: Float = 1e-5) -> Bool {
        topology.faces.contains { face in
            guard face.edge != nil else {
                return false
            }
            let points = facePositions(face.id)
            guard points.count > 3 else {
                return false
            }
            let normal = faceNormal(face.id)
            let centroid = faceCentroid(face.id)
            return points.contains { abs(simd_dot($0 - centroid, normal)) > tolerance }
        }
    }
}

// MARK: - Euler characteristic and genus

/// One connected piece of a surface and its topological invariants.
public struct SurfaceComponent: Sendable, Equatable {
    public var faces: [HalfEdgeTopology.FaceID]
    /// V - E + F, with each hole ring in a face counted as -1 (a holed face is not a disk).
    public var eulerCharacteristic: Int
    public var boundaryLoopCount: Int
    /// False if some edge's two half-edges run the same direction (faces can't be oriented consistently).
    public var isOrientable: Bool

    /// Genus from chi = 2 - 2g - b (orientable) or chi = 2 - g - b (non-orientable).
    /// Nil if the result is not a non-negative integer, which means the mesh is not a valid surface.
    public var genus: Int? {
        let value = 2 - eulerCharacteristic - boundaryLoopCount
        if isOrientable {
            return value >= 0 && value.isMultiple(of: 2) ? value / 2 : nil
        }
        return value >= 1 ? value : nil
    }
}

public extension HalfEdgeTopology {
    /// V - E + F over live elements, with hole rings counted as -1 each.
    var eulerCharacteristic: Int {
        surfaceComponents().reduce(0) { $0 + $1.eulerCharacteristic }
    }

    /// Connected pieces (faces joined across twin edges) with their invariants.
    func surfaceComponents() -> [SurfaceComponent] {
        // Union faces across twins.
        var parent = Array(faces.indices)
        func find(_ index: Int) -> Int {
            var root = index
            while parent[root] != root {
                parent[root] = parent[parent[root]]
                root = parent[root]
            }
            return root
        }
        for halfEdge in halfEdges where halfEdge.next != nil {
            if let face = halfEdge.face, let twin = halfEdge.twin, let other = halfEdges[twin.raw].face {
                parent[find(face.raw)] = find(other.raw)
            }
        }

        var componentFaces: [Int: [FaceID]] = [:]
        for face in faces where face.edge != nil {
            componentFaces[find(face.id.raw), default: []].append(face.id)
        }

        // Boundary loops belong to the component of the face on their inner side.
        var boundaryCounts: [Int: Int] = [:]
        var boundaryVertexComponent: [Int: Int] = [:]
        for halfEdge in halfEdges where halfEdge.next != nil && halfEdge.twin == nil {
            if let face = halfEdge.face {
                boundaryVertexComponent[halfEdge.origin.raw] = find(face.raw)
            }
        }
        for loop in boundaryLoops() {
            if let component = loop.lazy.compactMap({ boundaryVertexComponent[$0.raw] }).first {
                boundaryCounts[component, default: 0] += 1
            }
        }

        return componentFaces.values.sorted { $0[0].raw < $1[0].raw }.map { componentFaceIDs in
            var vertexSet = Set<Int>()
            var directed = Set<[Int]>()
            var undirected = Set<[Int]>()
            var orientable = true
            var holeRings = 0
            for face in componentFaceIDs {
                holeRings += faces[face.raw].holeEdges.count
                let loops = [faces[face.raw].edge!] + faces[face.raw].holeEdges
                for start in loops {
                    for halfEdge in collectHalfEdgeLoop(startEdge: start) {
                        let origin = halfEdges[halfEdge.raw].origin.raw
                        guard let destination = destViaNext(of: halfEdge)?.raw else {
                            continue
                        }
                        vertexSet.insert(origin)
                        if !directed.insert([origin, destination]).inserted {
                            orientable = false
                        }
                        undirected.insert([min(origin, destination), max(origin, destination)])
                    }
                }
            }
            let root = find(componentFaceIDs[0].raw)
            return SurfaceComponent(
                faces: componentFaceIDs,
                eulerCharacteristic: vertexSet.count - undirected.count + componentFaceIDs.count - holeRings,
                boundaryLoopCount: boundaryCounts[root] ?? 0,
                isOrientable: orientable
            )
        }
    }

    /// Every component has a valid (non-negative integer) genus.
    var hasConsistentGenus: Bool {
        surfaceComponents().allSatisfy { $0.genus != nil }
    }
}
