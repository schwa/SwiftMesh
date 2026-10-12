// Ported from Manifold (https://github.com/elalish/manifold): src/edge_op.cpp
// (RemoveDegenerates, CleanupTopology, SplitPinchedVerts, DedupeEdges, IsDuplicated,
// DedupeEdge, CollapseDegenerate, CollapseTri, FormLoop, RemoveIfFolded, UpdateVert,
// PairUp, SwapDegenerateEdges, IsDegenerate, SwapEdge, SplitQuad, Colinear, Continuous),
// src/impl.h (ForVert), src/shared.h (IsColinear). Copyright 2021 The Manifold Authors.
// Licensed under the Apache License, Version 2.0; see NOTICE.
//
// Property (attribute) handling in these functions is not ported yet; see #129.

import simd

/// Manifold's `IsColinear`: the short edge lies within epsilon of the long edge's line.
func isColinear(_ longEdge: SIMD3<Double>, _ shortEdge: SIMD3<Double>, _ epsilon: Double) -> Bool {
    simd_length_squared(simd_cross(longEdge, shortEdge)) <= simd_length_squared(longEdge) * epsilon * epsilon
}

/// Degenerate-triangle cleanup on Manifold's halfedge layout, where a half-edge stores only
/// its start vertex and its end is the next half-edge's start. Removed elements are marked:
/// vertices get NaN positions and half-edges get start = -1, pair = -1.
private struct DegenerateRemover {
    var start: [Int]
    var paired: [Int]
    var sourceCorner: [Int]
    var vertPos: [SIMD3<Double>]
    var vertNormal: [SIMD3<Double>]
    var faceNormal: [SIMD3<Double>]
    var triRef: [SIMD2<Int>]
    let epsilon: Double

    init(_ mesh: BooleanMesh) {
        start = mesh.halfedges.map(\.startVert)
        paired = mesh.halfedges.map(\.pairedHalfedge)
        sourceCorner = mesh.halfedges.map(\.sourceCorner)
        vertPos = mesh.vertPos
        vertNormal = mesh.vertNormal
        faceNormal = mesh.faceNormal
        triRef = mesh.triRef.count == mesh.numTri ? mesh.triRef : [SIMD2<Int>](repeating: SIMD2(0, -1), count: mesh.numTri)
        epsilon = mesh.epsilon
    }

    // MARK: Halfedge accessors

    static func next(_ edge: Int) -> Int { edge % 3 == 2 ? edge - 2 : edge + 1 }
    static func previous(_ edge: Int) -> Int { edge % 3 == 0 ? edge + 2 : edge - 1 }
    static func triOf(_ edge: Int) -> SIMD3<Int> {
        let second = next(edge)
        return SIMD3(edge, second, next(second))
    }

    func end(_ edge: Int) -> Int { start[Self.next(edge)] }
    func isValid(_ edge: Int) -> Bool { paired[edge] >= 0 }
    func isForward(_ edge: Int) -> Bool { start[edge] < end(edge) }
    var numTri: Int { start.count / 3 }

    mutating func setEnd(_ edge: Int, _ vert: Int) { start[Self.next(edge)] = vert }

    mutating func pairUp(_ a: Int, _ b: Int) {
        paired[a] = b
        paired[b] = a
    }

    mutating func pushHalfedge(start vert: Int, pair: Int) {
        start.append(vert)
        paired.append(pair)
        sourceCorner.append(-1)
    }

    /// Manifold's `ForVert`: every half-edge leaving `edge`'s start vertex, ending with `edge`.
    func forVert(_ edge: Int, _ body: (Int) -> Void) {
        var current = edge
        repeat {
            current = Self.next(paired[current])
            body(current)
        } while current != edge
    }

    // MARK: RemoveDegenerates

    mutating func removeDegenerates() {
        guard !start.isEmpty else {
            return
        }
        // CleanupTopology: split pinched verts, then edges shared by more than two triangles.
        splitPinchedVerts()
        dedupeEdges()

        var scratch: [Int] = []
        let halfedgeCount = start.count
        for edge in 0..<halfedgeCount {
            guard isValid(edge), simd_length_squared(vertPos[end(edge)] - vertPos[start[edge]]) <= epsilon * epsilon else {
                continue
            }
            // Collapse forward half-edges so that new verts are retained.
            collapseDegenerate(isForward(edge) ? edge : paired[edge], &scratch)
        }

        swapDegenerateEdges(&scratch)

        var edge = 0
        while edge < start.count {
            if isValid(edge), colinear(edge) {
                collapseDegenerate(edge, &scratch)
            }
            edge += 1
        }
    }

    // MARK: Topology cleanup

    private mutating func splitPinchedVerts() {
        var vertProcessed = [Bool](repeating: false, count: vertPos.count)
        var halfedgeProcessed = [Bool](repeating: false, count: start.count)
        for i in 0..<start.count where !halfedgeProcessed[i] {
            var vert = start[i]
            guard vert != -1 else {
                continue
            }
            if vertProcessed[vert] {
                vertPos.append(vertPos[vert])
                vertNormal.append(vertNormal[vert])
                vert = vertPos.count - 1
                var orbit: [Int] = []
                forVert(i) { orbit.append($0) }
                for current in orbit {
                    halfedgeProcessed[current] = true
                    start[current] = vert
                    setEnd(paired[current], vert)
                }
            } else {
                vertProcessed[vert] = true
                forVert(i) { halfedgeProcessed[$0] = true }
            }
        }
    }

    private mutating func dedupeEdges() {
        while true {
            var duplicates: [Int] = []
            var visited = [Bool](repeating: false, count: start.count)
            for i in 0..<start.count where !visited[i] {
                guard start[i] != -1, end(i) != -1 else {
                    continue
                }
                // Smallest half-edge per end vertex around this start vertex.
                var smallest: [Int: Int] = [:]
                forVert(i) { current in
                    visited[current] = true
                    guard start[current] != -1, end(current) != -1 else {
                        return
                    }
                    let endVert = end(current)
                    smallest[endVert] = min(smallest[endVert] ?? current, current)
                }
                // Every other half-edge to the same end vertex is a duplicate.
                forVert(i) { current in
                    guard start[current] != -1, end(current) != -1 else {
                        return
                    }
                    if smallest[end(current)] != current {
                        duplicates.append(current)
                    }
                }
            }
            var flagged = 0
            for edge in duplicates where isDuplicated(edge) {
                // An earlier repair in this pass may already have resolved this entry.
                dedupeEdge(edge)
                flagged += 1
            }
            if flagged == 0 {
                break
            }
        }
    }

    private func isDuplicated(_ edge: Int) -> Bool {
        let endVert = end(edge)
        var duplicated = false
        forVert(edge) { current in
            if current != edge, end(current) == endVert {
                duplicated = true
            }
        }
        return duplicated
    }

    /// Makes a 4-manifold edge distinct by duplicating its end vertex (and the start vertex
    /// if that becomes pinched).
    private mutating func dedupeEdge(_ edge: Int) {
        let nextEdge = Self.next(edge)
        let startVert = start[edge]
        let endVert = start[nextEdge]
        var current = paired[nextEdge]
        while current != edge {
            let vert = start[current]
            if vert == startVert {
                // A single topological unit needs two faces added to be split.
                let newVert = vertPos.count
                vertPos.append(vertPos[endVert])
                vertNormal.append(vertNormal[endVert])
                current = paired[Self.next(current)]
                let opposite = paired[nextEdge]
                updateVert(newVert, startEdge: current, endEdge: opposite)

                var newHalfedge = start.count
                var oldFace = current / 3
                var outsideVert = start[current]
                pushHalfedge(start: endVert, pair: -1)
                pushHalfedge(start: newVert, pair: -1)
                pushHalfedge(start: outsideVert, pair: -1)
                pairUp(newHalfedge + 2, paired[current])
                pairUp(newHalfedge + 1, current)
                triRef.append(triRef[oldFace])
                faceNormal.append(faceNormal[oldFace])

                newHalfedge += 3
                oldFace = opposite / 3
                outsideVert = start[opposite]
                pushHalfedge(start: newVert, pair: -1)
                pushHalfedge(start: endVert, pair: -1)
                pushHalfedge(start: outsideVert, pair: -1)
                pairUp(newHalfedge + 2, paired[opposite])
                pairUp(newHalfedge + 1, opposite)
                pairUp(newHalfedge, newHalfedge - 3)
                triRef.append(triRef[oldFace])
                faceNormal.append(faceNormal[oldFace])
                break
            }
            current = paired[Self.next(current)]
        }

        if current == edge {
            // A separate topological unit needs no new faces to be split.
            let newVert = vertPos.count
            vertPos.append(vertPos[endVert])
            vertNormal.append(vertNormal[endVert])
            relabelOrbit(Self.next(current), to: newVert)
        }

        // Orbit startVert: split it if the previous split pinched it.
        let pair = paired[edge]
        current = paired[Self.next(pair)]
        while current != pair {
            if start[current] == endVert {
                break // connected: not pinched
            }
            current = paired[Self.next(current)]
        }
        if current == pair {
            let newVert = vertPos.count
            vertPos.append(vertPos[endVert])
            vertNormal.append(vertNormal[endVert])
            relabelOrbit(Self.next(current), to: newVert)
        }
    }

    private mutating func relabelOrbit(_ edge: Int, to vert: Int) {
        var orbit: [Int] = []
        forVert(edge) { orbit.append($0) }
        for current in orbit {
            start[current] = vert
            setEnd(paired[current], vert)
        }
    }

    /// Walks CW around `startEdge`'s end from `startEdge` to `endEdge`, pointing edges at `vert`.
    private mutating func updateVert(_ vert: Int, startEdge: Int, endEdge: Int) {
        var current = startEdge
        while current != endEdge {
            setEnd(current, vert)
            current = Self.next(current)
            start[current] = vert
            current = paired[current]
            assert(current != startEdge, "infinite loop in decimator!")
        }
    }

    /// Instead of creating a non-manifold edge, duplicates both verts and reattaches the other way.
    private mutating func formLoop(_ current: Int, _ endEdge: Int) {
        let startVert = vertPos.count
        vertPos.append(vertPos[start[current]])
        vertNormal.append(vertNormal[start[current]])
        let endVert = vertPos.count
        vertPos.append(vertPos[end(current)])
        vertNormal.append(vertNormal[end(current)])

        let oldMatch = paired[current]
        let newMatch = paired[endEdge]
        updateVert(startVert, startEdge: oldMatch, endEdge: newMatch)
        updateVert(endVert, startEdge: endEdge, endEdge: current)
        pairUp(current, newMatch)
        pairUp(endEdge, oldMatch)
        removeIfFolded(endEdge)
    }

    private mutating func collapseTri(_ triEdge: SIMD3<Int>) {
        guard paired[triEdge[1]] != -1 else {
            return
        }
        pairUp(paired[triEdge[1]], paired[triEdge[2]])
        for i in 0..<3 {
            start[triEdge[i]] = -1
            paired[triEdge[i]] = -1
        }
    }

    private mutating func removeIfFolded(_ edge: Int) {
        let tri0 = Self.triOf(edge)
        let tri1 = Self.triOf(paired[edge])
        guard paired[tri0[1]] != -1 else {
            return
        }
        guard start[tri0[2]] == start[tri1[2]] else {
            return
        }
        if paired[tri0[1]] == tri1[2] {
            if paired[tri0[2]] == tri1[1] {
                for i in 0..<3 {
                    vertPos[start[tri0[i]]] = SIMD3(repeating: .nan)
                }
            } else {
                vertPos[start[tri0[1]]] = SIMD3(repeating: .nan)
            }
        } else if paired[tri0[2]] == tri1[1] {
            vertPos[start[tri1[1]]] = SIMD3(repeating: .nan)
        }
        pairUp(paired[tri0[1]], paired[tri1[2]])
        pairUp(paired[tri0[2]], paired[tri1[1]])
        for i in 0..<3 {
            start[tri0[i]] = -1
            paired[tri0[i]] = -1
            start[tri1[i]] = -1
            paired[tri1[i]] = -1
        }
    }

    /// Collapses a degenerate edge by removing its start vertex, splitting the mesh
    /// topologically if the collapse would create a 4-manifold edge.
    private mutating func collapseDegenerate(_ edge: Int, _ edges: inout [Int]) {
        let pair = paired[edge]
        guard pair >= 0 else {
            return
        }
        let tri0 = Self.triOf(edge)
        let tri1 = Self.triOf(pair)
        let startVert = start[tri0[0]]
        let endVert = start[tri0[1]]

        // Orbit endVert.
        edges.removeAll(keepingCapacity: true)
        var current = paired[tri0[1]]
        while current != tri1[2] {
            current = Self.next(current)
            edges.append(current)
            current = paired[current]
        }

        var startEdge = paired[tri1[1]]
        vertPos[startVert] = SIMD3(repeating: .nan)
        collapseTri(tri1)

        // Orbit startVert.
        current = startEdge
        while current != tri0[2] {
            current = Self.next(current)
            let vert = end(current)
            let nextEdge = paired[current]
            if let index = edges.firstIndex(where: { end($0) == vert }) {
                formLoop(edges[index], current)
                startEdge = nextEdge
                edges.removeSubrange(index...)
            }
            current = nextEdge
        }
        updateVert(endVert, startEdge: startEdge, endEdge: tri0[2])
        collapseTri(tri0)
        removeIfFolded(startEdge)
    }

    // MARK: Edge swaps

    /// (colinear, longest edge index within the triangle).
    private func isDegenerate(_ tri: Int) -> (colinear: Bool, longEdge: Int) {
        guard isValid(3 * tri) else {
            return (true, -1)
        }
        let v = (0..<3).map { vertPos[start[3 * tri + $0]] }
        let edgeVectors = [v[0] - v[1], v[1] - v[2], v[2] - v[0]]
        let lengths = edgeVectors.map(simd_length_squared)
        var longest = 0
        for i in 1..<3 where lengths[i] > lengths[longest] {
            longest = i
        }
        return (isColinear(edgeVectors[longest], edgeVectors[(longest + 1) % 3], epsilon), longest)
    }

    private mutating func swapDegenerateEdges(_ scratch: inout [Int]) {
        // A per-edge cap guards against swap cycles between coincident triangulations.
        let maxSwapsPerEdge = 255
        var swapCount = [Int](repeating: 0, count: start.count)
        var stack = Array(0..<numTri)
        while let tri = stack.popLast() {
            guard isValid(3 * tri) else {
                continue
            }
            let triResult = isDegenerate(tri)
            guard triResult.colinear else {
                continue
            }
            let edge = 3 * tri + triResult.longEdge
            let pair = paired[edge]
            let countIndex = min(edge, pair)
            guard swapCount[countIndex] < maxSwapsPerEdge else {
                continue
            }
            // Only swap if it reduces degenerates, or both stay degenerate with shorter longest edges.
            let pairResult = isDegenerate(pair / 3)
            if pairResult.colinear, pairResult.longEdge != pair % 3 {
                continue
            }
            let neighborTris = [
                paired[Self.next(edge)] / 3, paired[Self.previous(edge)] / 3,
                paired[Self.next(pair)] / 3, paired[Self.previous(pair)] / 3
            ]
            let newCenter = Self.previous(edge)
            let newCenterPair = Self.previous(pair)
            let nextPos = vertPos[start[newCenter]]
            let lastPos = vertPos[start[newCenterPair]]
            let basePos = vertPos[start[edge]]
            let endPos = vertPos[end(edge)]
            let a = nextPos - basePos
            let edgeVector = endPos - basePos

            if !pairResult.colinear {
                let newDiagonal = nextPos - lastPos
                if isColinear(newDiagonal, basePos - lastPos, epsilon) || isColinear(newDiagonal, endPos - lastPos, epsilon) {
                    let longEdge = 3 * (pair / 3) + pairResult.longEdge
                    if longEdge != pair, simd_dot(lastPos - basePos, endPos - nextPos) < 0,
                       splitQuad(longEdge, nextDiagonal: Self.next(longEdge) == pair) {
                        swapCount[countIndex] += 1
                        swapCount += [Int](repeating: 0, count: start.count - swapCount.count)
                        stack += [tri, pair / 3, numTri - 1, numTri - 2] + neighborTris
                        continue
                    }
                }
            }

            swapEdge(edge, simd_dot(a, edgeVector) / simd_length_squared(edgeVector))
            swapCount[countIndex] += 1
            if swapCount.count < start.count {
                swapCount += [Int](repeating: 0, count: start.count - swapCount.count)
            }
            if simd_length_squared(nextPos - lastPos) < epsilon * epsilon {
                collapseDegenerate(newCenter, &scratch)
            }
            stack += [tri, pair / 3] + neighborTris
        }
    }

    private mutating func swapEdge(_ edge: Int, _: Double) {
        let pair = paired[edge]
        let tri0 = Self.triOf(edge)
        let tri1 = Self.triOf(pair)
        // The 0-verts are swapped to the opposite 2-verts.
        start[tri0[0]] = start[tri1[2]]
        start[tri1[0]] = start[tri0[2]]
        pairUp(tri0[0], paired[tri1[2]])
        pairUp(tri1[0], paired[tri0[2]])
        pairUp(tri0[2], tri1[2])
        // Both triangles are now subsets of the neighboring triangle.
        let triangle0 = tri0[0] / 3
        let triangle1 = tri1[0] / 3
        faceNormal[triangle0] = faceNormal[triangle1]
        triRef[triangle0] = triRef[triangle1]

        // If the new edge already exists, duplicate the verts and split the mesh.
        var current = paired[tri1[0]]
        let endVert = end(tri1[1])
        while current != tri0[1] {
            current = Self.next(current)
            if end(current) == endVert {
                formLoop(tri0[2], current)
                removeIfFolded(tri0[2])
                return
            }
            current = paired[current]
        }
    }

    /// Splits `edge` and the opposite side of its quad by inserting a vertex, for a degenerate
    /// triangle that edge swaps can't fix. Returns false (no change) if the fan would be degenerate.
    private mutating func splitQuad(_ edge: Int, nextDiagonal nextDiag: Bool) -> Bool {
        let pair = paired[edge]
        let next0 = Self.next(edge)
        let prev0 = Self.previous(edge)
        let dp = paired[nextDiag ? next0 : prev0]
        let h1 = nextDiag ? Self.previous(dp) : Self.next(dp)
        let nextP0 = Self.next(pair)
        let prevP0 = Self.previous(pair)

        let edgeStart = start[edge]
        let edgeEnd = end(edge)
        let base = nextDiag ? start[prev0] : edgeStart
        let endV = nextDiag ? edgeEnd : start[prev0]
        let last = nextDiag ? edgeStart : edgeEnd
        let nextV = nextDiag ? start[h1] : end(h1)
        let c = start[prevP0]

        if isColinear(vertPos[endV] - vertPos[last], vertPos[nextV] - vertPos[last], epsilon) {
            return false
        }
        let ps = vertPos[edgeStart]
        let edgeVector = vertPos[edgeEnd] - ps
        let center = (vertPos[start[h1]] + vertPos[end(h1)]) / 2
        let length2 = simd_dot(edgeVector, edgeVector)
        let t = length2 > 0 ? simd_clamp(simd_dot(center - ps, edgeVector) / length2, 0, 1) : 0.5
        let m = vertPos.count
        vertPos.append(ps + t * edgeVector)
        vertNormal.append(safeNormalize(vertNormal[edgeStart] * (1 - t) + vertNormal[edgeEnd] * t))

        let extC0 = paired[prevP0]
        let extC1 = paired[nextP0]
        let extA = paired[nextDiag ? prev0 : next0]
        let extB0 = paired[nextDiag ? Self.next(dp) : Self.previous(dp)]
        let extB1 = paired[h1]

        let triA = edge / 3
        let triB = h1 / 3
        let triC = pair / 3
        let triN = numTri
        let triS = triN + 1
        for _ in 0..<6 {
            pushHalfedge(start: -1, pair: -1)
        }
        triRef += [triRef[triB], triRef[triC]]
        faceNormal += [faceNormal[triB], faceNormal[triC]]

        func setTri(_ tri: Int, _ verts: SIMD3<Int>) {
            for i in 0..<3 {
                start[3 * tri + i] = verts[i]
                sourceCorner[3 * tri + i] = -1
            }
        }
        setTri(triC, SIMD3(edgeEnd, m, c))
        setTri(triS, SIMD3(m, edgeStart, c))
        pairUp(3 * triC + 2, extC0)
        pairUp(3 * triS + 1, extC1)
        pairUp(3 * triC + 1, 3 * triS + 2)
        if nextDiag {
            setTri(triA, SIMD3(last, m, base))
            setTri(triB, SIMD3(m, endV, nextV))
            setTri(triN, SIMD3(m, nextV, base))
            pairUp(3 * triA, 3 * triS)
            pairUp(3 * triA + 1, 3 * triN + 2)
            pairUp(3 * triA + 2, extA)
            pairUp(3 * triB, 3 * triC)
            pairUp(3 * triB + 1, extB0)
            pairUp(3 * triB + 2, 3 * triN)
            pairUp(3 * triN + 1, extB1)
        } else {
            setTri(triA, SIMD3(m, last, endV))
            setTri(triB, SIMD3(base, m, nextV))
            setTri(triN, SIMD3(m, endV, nextV))
            pairUp(3 * triA, 3 * triC)
            pairUp(3 * triA + 1, extA)
            pairUp(3 * triA + 2, 3 * triN)
            pairUp(3 * triB, 3 * triS)
            pairUp(3 * triB + 1, 3 * triN + 2)
            pairUp(3 * triB + 2, extB0)
            pairUp(3 * triN + 1, extB1)
        }
        return true
    }

    // MARK: Colinear collapse

    /// Same source face on both sides (no property data yet, so faces decide; see #129).
    private func continuous(_ edge: Int) -> Bool {
        triRef[edge / 3] == triRef[paired[edge] / 3]
    }

    /// Whether collapsing `edge` (moving its start onto its end) keeps every surrounding
    /// triangle in plane, un-inverted, and property boundaries aligned.
    private func colinear(_ edge: Int) -> Bool {
        let pair = paired[edge]
        let tri0 = Self.triOf(edge)
        let tri1 = Self.triOf(pair)
        let startVert = start[tri0[0]]
        let endVert = start[tri0[1]]
        let pNew = vertPos[endVert]
        let pOld = vertPos[startVert]

        func alignedProps(_ current: Int, _ pNext: SIMD3<Double>) -> Bool {
            if continuous(current) {
                return true
            }
            let across = pNext - pNew
            return simd_length_squared(simd_cross(across, pOld - pNew)) <= epsilon * epsilon * simd_length_squared(across)
        }

        // Orbit startVert.
        let startEdge = paired[tri1[1]]
        var pLast = vertPos[start[tri1[2]]]
        guard alignedProps(startEdge, pLast) else {
            return false
        }
        var current = startEdge
        while current != tri0[2] {
            current = Self.next(current)
            let pNext = vertPos[end(current)]
            let tri = current / 3
            if abs(simd_dot(pNew - pOld, faceNormal[tri])) > epsilon {
                return false
            }
            // Don't collapse if it would invert a triangle.
            let project = axisAlignedProjection(faceNormal[tri])
            if ccw(project(pNext), project(pLast), project(pNew), epsilon) <= 0 || !alignedProps(current, pNext) {
                return false
            }
            pLast = pNext
            current = paired[current]
        }
        return true
    }

    // MARK: Output

    /// Drops removed triangles and unused vertices (Manifold's compaction after RemoveDegenerates).
    func compacted() -> BooleanMesh {
        var mesh = BooleanMesh()
        var keptTriangles: [Int] = []
        var newTriangle = [Int](repeating: -1, count: numTri)
        for tri in 0..<numTri where isValid(3 * tri) {
            newTriangle[tri] = keptTriangles.count
            keptTriangles.append(tri)
        }
        var vertexMap = [Int](repeating: -1, count: vertPos.count)
        for tri in keptTriangles {
            for corner in 0..<3 {
                let vert = start[3 * tri + corner]
                if vertexMap[vert] < 0 {
                    vertexMap[vert] = mesh.vertPos.count
                    mesh.vertPos.append(vertPos[vert])
                    mesh.vertNormal.append(vertNormal[vert])
                }
            }
        }
        for tri in keptTriangles {
            for corner in 0..<3 {
                let edge = 3 * tri + corner
                let pair = paired[edge]
                mesh.halfedges.append(.init(
                    startVert: vertexMap[start[edge]],
                    endVert: vertexMap[end(edge)],
                    pairedHalfedge: 3 * newTriangle[pair / 3] + pair % 3,
                    sourceCorner: sourceCorner[edge]
                ))
            }
            mesh.faceNormal.append(faceNormal[tri])
            mesh.triRef.append(triRef[tri])
        }
        mesh.calculateBounds()
        mesh.epsilon = max(mesh.epsilon, epsilon)
        // Merging verts changes their pseudo-normals.
        let faceNormals = mesh.faceNormal
        mesh.setFaceAndVertNormals()
        mesh.faceNormal = faceNormals
        return mesh
    }
}

extension BooleanMesh {
    /// Removes degenerate triangles and collapses colinear edges while staying manifold
    /// (Manifold's `RemoveDegenerates` followed by compaction).
    package func removingDegenerates() -> BooleanMesh {
        var remover = DegenerateRemover(self)
        remover.removeDegenerates()
        return remover.compacted()
    }

    /// Triangles whose longest edge is within epsilon of colinear with the next one.
    package var degenerateTriangleCount: Int {
        (0..<numTri).filter { tri in
            let v = (0..<3).map { vertPos[halfedges[3 * tri + $0].startVert] }
            let edges = [v[0] - v[1], v[1] - v[2], v[2] - v[0]]
            let lengths = edges.map(simd_length_squared)
            var longest = 0
            for i in 1..<3 where lengths[i] > lengths[longest] {
                longest = i
            }
            return isColinear(edges[longest], edges[(longest + 1) % 3], epsilon)
        }.count
    }
}
