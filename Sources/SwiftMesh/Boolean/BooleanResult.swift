// Ported from Manifold (https://github.com/elalish/manifold): src/boolean_result.cpp
// (Boolean3::Result through face assembly: SizeOutput, AddNewEdgeVerts, PairUp,
// AppendPartialEdges, AppendNewEdges, AppendWholeEdges), src/boolean3.cpp (Boolean3
// constructor), src/face_op.cpp (Face2Tri, AssembleHalfedges, ProjectPolygons), and
// src/shared.h (GetAxisAlignedProjection). Copyright 2021 The Manifold Authors.
// Licensed under the Apache License, Version 2.0; see NOTICE.

import simd

/// The three Boolean operations (Manifold's `OpType`).
package enum BooleanOperation: Sendable {
    case union
    case difference
    case intersection
}

/// The Boolean result as polygonal faces, before triangulation.
package struct BooleanFaces: Sendable {
    package var vertPos: [SIMD3<Double>] = []
    /// Face f owns half-edges `faceEdge[f] ..< faceEdge[f + 1]`.
    package var faceEdge: [Int] = [0]
    /// Half-edges grouped by face; `pairedHalfedge` indexes this array.
    package var halfedges: [BooleanMesh.Halfedge] = []
    package var faceNormal: [SIMD3<Double>] = []
    /// Which input face each output face came from.
    package var faceSource: [(fromQ: Bool, face: Int)] = []
    /// Output vertices below this index are retained input vertices; the rest are new.
    package var retainedVertexCount = 0
    package var epsilon: Double = 0

    package var numFace: Int { faceEdge.count - 1 }
}

/// Runs the robust Boolean of `inP` and `inQ` up to polygonal faces (Manifold's `Boolean3`).
package struct BooleanAssembler {
    let inP: BooleanMesh
    let inQ: BooleanMesh
    let operation: BooleanOperation

    package init(_ inP: BooleanMesh, _ inQ: BooleanMesh, operation: BooleanOperation) {
        self.inP = inP
        self.inQ = inQ
        self.operation = operation
    }

    private struct EdgePos {
        var edgePos: Double
        var vert: Int
        var collisionID: Int
        var isStart: Bool

        static func < (a: Self, b: Self) -> Bool {
            // collisionID breaks ties so the order is deterministic.
            a.edgePos < b.edgePos || (a.edgePos == b.edgePos && a.collisionID < b.collisionID)
        }
    }

    package func assemble() -> BooleanFaces {
        // Symbolic perturbation: union expands P; difference and intersection contract it.
        let kernels = BooleanKernels(inP: inP, inQ: inQ, expandP: operation == .union)
        var xv12 = BooleanIntersections()
        var xv21 = BooleanIntersections()
        var w03 = [Int](repeating: 0, count: inP.numVert)
        var w30 = [Int](repeating: 0, count: inQ.numVert)
        let overlap = inP.numTri > 0 && inQ.numTri > 0
            && all(inP.boundsMin .<= inQ.boundsMax) && all(inQ.boundsMin .<= inP.boundsMax)
        if overlap {
            let colliderP = inP.makeFaceCollider()
            let colliderQ = inQ.makeFaceCollider()
            xv12 = kernels.intersect12(forward: true, colliderB: colliderQ)
            xv21 = kernels.intersect12(forward: false, colliderB: colliderP)
            w03 = kernels.winding03(forward: true, p1q2: xv12.p1q2, colliderB: colliderQ)
            w30 = kernels.winding03(forward: false, p1q2: xv21.p1q2, colliderB: colliderP)
        }

        // Winding numbers to inclusion: how many times (and which way) each element is kept.
        let c1 = operation == .intersection ? 0 : 1
        let c2 = operation == .union ? 1 : 0
        let c3 = operation == .intersection ? 1 : -1
        let i12 = xv12.x12.map { c3 * $0 }
        let i21 = xv21.x12.map { c3 * $0 }
        let i03 = w03.map { c1 + c3 * $0 }
        let i30 = w30.map { c2 + c3 * $0 }
        let invertQ = operation == .difference

        // Output vertex numbering: retained P, retained Q, new P-edge verts, new Q-edge verts.
        var numVertR = 0
        func scan(_ inclusion: [Int]) -> [Int] {
            inclusion.map { value in
                defer { numVertR += abs(value) }
                return numVertR
            }
        }
        let vP2R = scan(i03)
        let vQ2R = scan(i30)
        let retained = numVertR
        let v12R = scan(i12)
        let v21R = scan(i21)

        var out = BooleanFaces()
        out.retainedVertexCount = retained
        out.epsilon = max(inP.epsilon, inQ.epsilon)
        guard numVertR > 0 else {
            return out
        }
        out.vertPos = [SIMD3<Double>](repeating: .zero, count: numVertR)
        func duplicate(_ inclusion: [Int], _ remap: [Int], _ positions: [SIMD3<Double>]) {
            for (vertex, value) in inclusion.enumerated() {
                for copy in 0..<abs(value) {
                    out.vertPos[remap[vertex] + copy] = positions[vertex]
                }
            }
        }
        duplicate(i03, vP2R, inP.vertPos)
        duplicate(i30, vQ2R, inQ.vertPos)
        duplicate(i12, v12R, xv12.v12)
        duplicate(i21, v21R, xv21.v12)

        // New verts on intersected edges, and on the new edges where a P face meets a Q face.
        var edgesP: [Int: [EdgePos]] = [:]
        var edgesQ: [Int: [EdgePos]] = [:]
        var edgesNew: [SIMD2<Int>: [EdgePos]] = [:]
        func addNewEdgeVerts(_ edges: inout [Int: [EdgePos]], _ p1q2: [SIMD2<Int>], _ inclusions: [Int], _ vertR: [Int], _ halfedges: [BooleanMesh.Halfedge], forward: Bool, offset: Int) {
            for i in p1q2.indices {
                let edgeP = p1q2[i][forward ? 0 : 1]
                let faceQ = p1q2[i][forward ? 1 : 0]
                let vert = vertR[i]
                let inclusion = inclusions[i]
                var keyRight = SIMD2(halfedges[edgeP].pairedHalfedge / 3, faceQ)
                var keyLeft = SIMD2(edgeP / 3, faceQ)
                if !forward {
                    keyRight = SIMD2(keyRight.y, keyRight.x)
                    keyLeft = SIMD2(keyLeft.y, keyLeft.x)
                }
                let direction = inclusion < 0
                for copy in 0..<abs(inclusion) {
                    let base = EdgePos(edgePos: 0, vert: vert + copy, collisionID: i + offset, isStart: direction)
                    edges[edgeP, default: []].append(base)
                    // Manifold builds these flags before toggling `direction`, so they are
                    // direction ^ !forward (right face) and direction ^ forward (left face).
                    var right = base
                    right.isStart = direction != !forward
                    edgesNew[keyRight, default: []].append(right)
                    var left = base
                    left.isStart = direction != forward
                    edgesNew[keyLeft, default: []].append(left)
                }
            }
        }
        addNewEdgeVerts(&edgesP, xv12.p1q2, i12, v12R, inP.halfedges, forward: true, offset: 0)
        addNewEdgeVerts(&edgesQ, xv21.p1q2, i21, v21R, inQ.halfedges, forward: false, offset: xv12.p1q2.count)

        // SizeOutput: edges per face, which faces survive, and their normals.
        var sidesPerFace = [Int](repeating: 0, count: inP.numTri + inQ.numTri)
        for triangle in 0..<inP.numTri {
            for corner in 0..<3 {
                sidesPerFace[triangle] += abs(i03[inP.halfedges[3 * triangle + corner].startVert])
            }
        }
        for triangle in 0..<inQ.numTri {
            for corner in 0..<3 {
                sidesPerFace[inP.numTri + triangle] += abs(i30[inQ.halfedges[3 * triangle + corner].startVert])
            }
        }
        for (index, pair) in xv12.p1q2.enumerated() {
            let inclusion = abs(i12[index])
            sidesPerFace[inP.numTri + pair.y] += inclusion
            sidesPerFace[pair.x / 3] += inclusion
            sidesPerFace[inP.halfedges[pair.x].pairedHalfedge / 3] += inclusion
        }
        for (index, pair) in xv21.p1q2.enumerated() {
            let inclusion = abs(i21[index])
            sidesPerFace[pair.x] += inclusion
            sidesPerFace[inP.numTri + pair.y / 3] += inclusion
            sidesPerFace[inP.numTri + inQ.halfedges[pair.y].pairedHalfedge / 3] += inclusion
        }
        var facePQ2R = [Int](repeating: 0, count: sidesPerFace.count)
        var keptFaces = 0
        for face in sidesPerFace.indices {
            facePQ2R[face] = keptFaces
            if sidesPerFace[face] > 0 {
                keptFaces += 1
                let fromQ = face >= inP.numTri
                let source = fromQ ? face - inP.numTri : face
                let normal = fromQ ? inQ.faceNormal[source] : inP.faceNormal[source]
                out.faceNormal.append(fromQ && invertQ ? -normal : normal)
                out.faceSource.append((fromQ, source))
                out.faceEdge.append(out.faceEdge.last! + sidesPerFace[face])
            }
        }
        out.halfedges = [BooleanMesh.Halfedge](repeating: BooleanMesh.Halfedge(startVert: -1, endVert: -1, pairedHalfedge: -1, sourceCorner: -1), count: out.faceEdge.last!)
        var facePointer = Array(out.faceEdge.dropLast())

        /// Pairs start verts with end verts in edge order and emits each edge into two faces.
        func pairUp(_ positions: [EdgePos], left faceLeft: Int, right faceRight: Int) {
            assert(positions.count.isMultiple(of: 2), "Non-manifold edge! Not an even number of points.")
            let starts = positions.filter(\.isStart).sorted(by: <)
            let ends = positions.filter { !$0.isStart }.sorted(by: <)
            assert(starts.count == ends.count, "Non-manifold edge!")
            for (start, end) in zip(starts, ends) {
                let forwardEdge = facePointer[faceLeft]
                facePointer[faceLeft] += 1
                let backwardEdge = facePointer[faceRight]
                facePointer[faceRight] += 1
                out.halfedges[forwardEdge] = .init(startVert: start.vert, endVert: end.vert, pairedHalfedge: backwardEdge, sourceCorner: -1)
                out.halfedges[backwardEdge] = .init(startVert: end.vert, endVert: start.vert, pairedHalfedge: forwardEdge, sourceCorner: -1)
            }
        }

        // AppendPartialEdges: intersected input edges, split at their new verts.
        var wholeP = [Bool](repeating: true, count: inP.halfedges.count)
        var wholeQ = [Bool](repeating: true, count: inQ.halfedges.count)
        func appendPartialEdges(_ edges: [Int: [EdgePos]], _ mesh: BooleanMesh, _ whole: inout [Bool], _ inclusion: [Int], _ vertR: [Int], faceOffset: Int) {
            for edgeP in edges.keys.sorted() {
                var positions = edges[edgeP]!.enumerated().sorted { $0.element < $1.element || (!($1.element < $0.element) && $0.offset < $1.offset) }.map(\.element)
                let pairP = mesh.halfedges[edgeP].pairedHalfedge
                whole[edgeP] = false
                whole[pairP] = false
                let vStart = mesh.halfedges[edgeP].startVert
                let vEnd = mesh.halfedges[edgeP].endVert
                let edgeVector = mesh.vertPos[vEnd] - mesh.vertPos[vStart]
                for index in positions.indices {
                    positions[index].edgePos = simd_dot(out.vertPos[positions[index].vert], edgeVector)
                }
                for (vertex, isStart) in [(vStart, inclusion[vStart] > 0), (vEnd, inclusion[vEnd] < 0)] {
                    let position = simd_dot(out.vertPos[vertR[vertex]], edgeVector)
                    for copy in 0..<abs(inclusion[vertex]) {
                        positions.append(EdgePos(edgePos: position, vert: vertR[vertex] + copy, collisionID: .max, isStart: isStart))
                    }
                }
                pairUp(positions, left: facePQ2R[faceOffset + edgeP / 3], right: facePQ2R[faceOffset + pairP / 3])
            }
        }
        appendPartialEdges(edgesP, inP, &wholeP, i03, vP2R, faceOffset: 0)
        appendPartialEdges(edgesQ, inQ, &wholeQ, i30, vQ2R, faceOffset: inP.numTri)

        // AppendNewEdges: where a P face crosses a Q face, ordered along the longest axis.
        for key in edgesNew.keys.sorted(by: { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }) {
            var positions = edgesNew[key]!.enumerated().sorted { $0.element < $1.element || (!($1.element < $0.element) && $0.offset < $1.offset) }.map(\.element)
            var low = SIMD3<Double>(repeating: .infinity)
            var high = SIMD3<Double>(repeating: -.infinity)
            for position in positions {
                low = simd_min(low, out.vertPos[position.vert])
                high = simd_max(high, out.vertPos[position.vert])
            }
            let size = high - low
            let axis = size.x > size.y && size.x > size.z ? 0 : (size.y > size.z ? 1 : 2)
            for index in positions.indices {
                positions[index].edgePos = out.vertPos[positions[index].vert][axis]
            }
            pairUp(positions, left: facePQ2R[key.x], right: facePQ2R[inP.numTri + key.y])
        }

        // AppendWholeEdges: unbroken input edges, duplicated by inclusion.
        func appendWholeEdges(_ mesh: BooleanMesh, _ whole: [Bool], _ inclusion: [Int], _ vertR: [Int], faceOffset: Int) {
            for index in mesh.halfedges.indices where whole[index] {
                var startVert = mesh.halfedges[index].startVert
                var endVert = mesh.halfedges[BooleanMesh.nextHalfedge(index)].startVert
                guard startVert < endVert else {
                    continue
                }
                let value = inclusion[startVert]
                guard value != 0 else {
                    continue
                }
                if value < 0 {
                    swap(&startVert, &endVert)
                }
                startVert = vertR[startVert]
                endVert = vertR[endVert]
                let pair = mesh.halfedges[index].pairedHalfedge
                let newFace = facePQ2R[faceOffset + index / 3]
                let faceRight = facePQ2R[faceOffset + pair / 3]
                for _ in 0..<abs(value) {
                    let forwardEdge = facePointer[newFace]
                    facePointer[newFace] += 1
                    let backwardEdge = facePointer[faceRight]
                    facePointer[faceRight] += 1
                    out.halfedges[forwardEdge] = .init(startVert: startVert, endVert: endVert, pairedHalfedge: backwardEdge, sourceCorner: mesh.halfedges[index].sourceCorner)
                    out.halfedges[backwardEdge] = .init(startVert: endVert, endVert: startVert, pairedHalfedge: forwardEdge, sourceCorner: mesh.halfedges[pair].sourceCorner)
                    startVert += 1
                    endVert += 1
                }
            }
        }
        appendWholeEdges(inP, wholeP, i03, vP2R, faceOffset: 0)
        appendWholeEdges(inQ, wholeQ, i30, vQ2R, faceOffset: inP.numTri)
        return out
    }
}

// MARK: - Face2Tri

/// Manifold's `GetAxisAlignedProjection`: drop the normal's dominant axis, keeping CCW order.
func axisAlignedProjection(_ normal: SIMD3<Double>) -> (SIMD3<Double>) -> SIMD2<Double> {
    let absNormal = simd_abs(normal)
    if absNormal.z > absNormal.x, absNormal.z > absNormal.y {
        let sign: Double = normal.z < 0 ? -1 : 1
        return { SIMD2(sign * $0.x, $0.y) }
    }
    if absNormal.y > absNormal.x {
        let sign: Double = normal.y < 0 ? -1 : 1
        return { SIMD2(sign * $0.z, $0.x) }
    }
    let sign: Double = normal.x < 0 ? -1 : 1
    return { SIMD2(sign * $0.y, $0.z) }
}

extension BooleanFaces {
    /// Manifold's `AssembleHalfedges`: chains a face's half-edges into loops of edge indices.
    func assembleLoops(face: Int) -> [[Int]] {
        let range = faceEdge[face]..<faceEdge[face + 1]
        // A multimap from start vertex to edges, smallest key first, insertion order within a key.
        var byStart: [Int: [Int]] = [:]
        for edge in range {
            byStart[halfedges[edge].startVert, default: []].append(edge)
        }
        func take(_ vertex: Int) -> Int? {
            guard var list = byStart[vertex], !list.isEmpty else {
                return nil
            }
            let edge = list.removeFirst()
            byStart[vertex] = list.isEmpty ? nil : list
            return edge
        }
        var loops: [[Int]] = []
        while let smallest = byStart.keys.min(), let start = take(smallest) {
            var loop = [start]
            var current = start
            while true {
                guard let next = take(halfedges[current].endVert) else {
                    break
                }
                if next == start {
                    break
                }
                loop.append(next)
                current = next
            }
            loops.append(loop)
        }
        return loops
    }

    /// Triangulates every face and returns a closed triangle mesh (Manifold's `Face2Tri`).
    ///
    /// Triangle half-edges on a face's contour inherit the contour's pairing across faces;
    /// interior diagonals pair within the face.
    package func triangulated() -> BooleanMesh {
        var mesh = BooleanMesh()
        mesh.vertPos = vertPos
        // contour edge -> output triangle half-edge
        var contourToTri = [Int](repeating: -1, count: halfedges.count)
        var triangleFace: [Int] = []

        for face in 0..<numFace {
            let range = faceEdge[face]..<faceEdge[face + 1]
            guard range.count >= 3 else {
                continue
            }
            let loops = assembleLoops(face: face)
            var next = [Int: Int]()
            for loop in loops {
                for (index, edge) in loop.enumerated() {
                    next[edge] = loop[(index + 1) % loop.count]
                }
            }
            // Triangles as triples of contour edge indices (each names its start corner).
            var triangles: [SIMD3<Int>]
            if range.count == 3, loops.count == 1 {
                triangles = [SIMD3(loops[0][0], loops[0][1], loops[0][2])]
            } else if range.count == 4, loops.count == 1 {
                triangles = quadTriangles(loops[0], normal: faceNormal[face])
            } else {
                let project = axisAlignedProjection(faceNormal[face])
                let polygons = loops.map { loop in
                    loop.map { PolyVert(pos: project(vertPos[halfedges[$0].startVert]), idx: $0) }
                }
                triangles = triangulate(polygons, epsilon: epsilon, allowConvex: false)
            }
            var interior: [SIMD2<Int>: Int] = [:]
            for triangle in triangles {
                let base = mesh.halfedges.count
                for corner in 0..<3 {
                    let edge = triangle[corner]
                    let following = triangle[(corner + 1) % 3]
                    let output = base + corner
                    mesh.halfedges.append(.init(startVert: halfedges[edge].startVert, endVert: halfedges[following].startVert, pairedHalfedge: -1, sourceCorner: halfedges[edge].sourceCorner))
                    if next[edge] == following {
                        contourToTri[edge] = output
                    } else if let partner = interior.removeValue(forKey: SIMD2(following, edge)) {
                        mesh.halfedges[output].pairedHalfedge = partner
                        mesh.halfedges[partner].pairedHalfedge = output
                    } else {
                        interior[SIMD2(edge, following)] = output
                    }
                }
                triangleFace.append(face)
            }
        }
        // Contour edges pair with the triangle edge on the other side of their paired contour.
        for edge in halfedges.indices where contourToTri[edge] >= 0 {
            let partnerContour = halfedges[edge].pairedHalfedge
            if partnerContour >= 0, contourToTri[partnerContour] >= 0 {
                mesh.halfedges[contourToTri[edge]].pairedHalfedge = contourToTri[partnerContour]
            }
        }
        mesh.faceNormal = triangleFace.map { faceNormal[$0] }
        mesh.calculateBounds()
        mesh.epsilon = max(mesh.epsilon, epsilon)
        mesh.setFaceAndVertNormals()
        // Keep the source faces' normals: they are more accurate than recomputed ones for slivers.
        mesh.faceNormal = triangleFace.map { faceNormal[$0] }
        mesh.triRef = triangleFace.map { SIMD2(faceSource[$0].fromQ ? 1 : 0, faceSource[$0].face) }
        return mesh
    }

    /// Manifold's quad case: pick the diagonal whose triangles are both CCW, preferring the shorter.
    private func quadTriangles(_ quad: [Int], normal: SIMD3<Double>) -> [SIMD3<Int>] {
        let project = axisAlignedProjection(normal)
        func isCCW(_ t: SIMD3<Int>) -> Bool {
            ccw(project(vertPos[halfedges[t.x].startVert]), project(vertPos[halfedges[t.y].startVert]), project(vertPos[halfedges[t.z].startVert]), epsilon) >= 0
        }
        let choices = [
            [SIMD3(quad[0], quad[1], quad[2]), SIMD3(quad[0], quad[2], quad[3])],
            [SIMD3(quad[1], quad[2], quad[3]), SIMD3(quad[0], quad[1], quad[3])]
        ]
        var choice = 0
        if !(isCCW(choices[0][0]) && isCCW(choices[0][1])) {
            choice = 1
        } else if isCCW(choices[1][0]), isCCW(choices[1][1]) {
            let diagonal0 = vertPos[halfedges[quad[0]].startVert] - vertPos[halfedges[quad[2]].startVert]
            let diagonal1 = vertPos[halfedges[quad[1]].startVert] - vertPos[halfedges[quad[3]].startVert]
            if simd_length_squared(diagonal0) > simd_length_squared(diagonal1) {
                choice = 1
            }
        }
        return choices[choice]
    }
}
