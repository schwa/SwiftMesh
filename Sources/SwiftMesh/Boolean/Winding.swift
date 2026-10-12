// Ported from Manifold (https://github.com/elalish/manifold): src/boolean3.cpp (Winding03,
// PointWinding), src/disjoint_sets.h. Copyright 2021 The Manifold Authors.
// Licensed under the Apache License, Version 2.0; see NOTICE.

import simd

/// Serial union-find with path halving and union by rank.
private struct DisjointSets {
    private var parent: [Int]
    private var rank: [Int]

    init(count: Int) {
        parent = Array(0..<count)
        rank = [Int](repeating: 0, count: count)
    }

    mutating func find(_ id: Int) -> Int {
        var node = id
        while parent[node] != node {
            parent[node] = parent[parent[node]]
            node = parent[node]
        }
        return node
    }

    mutating func unite(_ a: Int, _ b: Int) {
        var rootA = find(a)
        var rootB = find(b)
        guard rootA != rootB else {
            return
        }
        if rank[rootA] > rank[rootB] {
            swap(&rootA, &rootB)
        }
        parent[rootA] = rootB
        if rank[rootA] == rank[rootB] {
            rank[rootB] += 1
        }
    }
}

extension BooleanKernels {
    /// Winding03: the winding number of every vertex of A relative to B (forward: A = P).
    ///
    /// Vertices joined by edges that no B face crosses (`p1q2` from `intersect12` in the same
    /// direction) share a winding number, so only one vertex per component is tested with
    /// Kernel02 along +z; the rest are flood-filled.
    func winding03(forward: Bool, p1q2: [SIMD2<Int>], colliderB: Collider) -> [Int] {
        let inA = forward ? inP : inQ
        let index = forward ? 0 : 1
        let brokenEdges = Set(p1q2.map { $0[index] })

        var components = DisjointSets(count: inA.numVert)
        for (edge, halfedge) in inA.halfedges.enumerated() where halfedge.startVert < halfedge.endVert {
            if !brokenEdges.contains(edge) {
                components.unite(halfedge.startVert, halfedge.endVert)
            }
        }
        var roots: [Int] = []
        var isRoot = [Bool](repeating: false, count: inA.numVert)
        for vertex in 0..<inA.numVert {
            let root = components.find(vertex)
            if !isRoot[root] {
                isRoot[root] = true
                roots.append(root)
            }
        }

        var winding = [Int](repeating: 0, count: inA.numVert)
        for root in roots {
            colliderB.forEachOverlapXY(inA.vertPos[root]) { face in
                let (s02, z02) = kernel02(root, face, forward: forward)
                if z02.isFinite {
                    winding[root] += s02 * (forward ? 1 : -1)
                }
            }
        }
        for vertex in 0..<inA.numVert {
            let root = components.find(vertex)
            if root != vertex {
                winding[vertex] = winding[root]
            }
        }
        return winding
    }
}

extension BooleanMesh {
    /// Manifold's `PointWinding`: the winding number of each point relative to this closed mesh.
    ///
    /// Points carry no perturbation (zero normals), so points exactly on the surface resolve by
    /// the mesh side's tiebreak alone.
    func pointWinding(_ points: [SIMD3<Double>], collider: Collider? = nil) -> [Int] {
        var winding = [Int](repeating: 0, count: points.count)
        guard !points.isEmpty, numTri > 0 else {
            return winding
        }
        // Points outside the bounding box have winding 0.
        let queryIndices = points.indices.filter { index in
            let p = points[index]
            return p.x >= boundsMin.x && p.y >= boundsMin.y && p.z >= boundsMin.z
                && p.x <= boundsMax.x && p.y <= boundsMax.y && p.z <= boundsMax.z
        }
        guard !queryIndices.isEmpty else {
            return winding
        }
        var pointMesh = BooleanMesh()
        pointMesh.vertPos = queryIndices.map { points[$0] }
        pointMesh.vertNormal = [SIMD3<Double>](repeating: .zero, count: queryIndices.count)
        let kernels = BooleanKernels(inP: pointMesh, inQ: self, expandP: false)
        let collider = collider ?? makeFaceCollider()
        for (local, input) in queryIndices.enumerated() {
            collider.forEachOverlapXY(pointMesh.vertPos[local]) { face in
                let (s02, z02) = kernels.kernel02(local, face, forward: true)
                if z02.isFinite {
                    winding[input] += s02
                }
            }
        }
        return winding
    }
}

public extension Mesh {
    /// Robust winding numbers of points relative to this closed mesh: 1 inside, 0 outside,
    /// and higher inside nested shells. Exact ties are broken consistently rather than with a
    /// tolerance, so points on the surface get a definite answer.
    ///
    /// - Returns: One winding number per point, or `nil` if the mesh is not a closed manifold.
    func windingNumbers(at points: [SIMD3<Float>]) -> [Int]? {
        guard let boolean = try? BooleanMesh(mesh: self) else {
            return nil
        }
        return boolean.pointWinding(points.map { SIMD3<Double>($0) })
    }
}
