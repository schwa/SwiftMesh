// Ported from Manifold (https://github.com/elalish/manifold): src/boolean3.cpp (Shadow01,
// Kernel11, Kernel02, Kernel12, Intersect12), src/boolean3.h (Intersections), src/shared.h
// (Shadows, withSign, Interpolate, Intersect). Copyright 2021 The Manifold Authors.
// Licensed under the Apache License, Version 2.0; see NOTICE.
//
// Notation follows Manifold: inputs P and Q; digits are dimensions (0 vertex, 1 edge,
// 2 face), so p1q2 pairs an edge of P with a face of Q. Each kernel builds on the
// lower-dimensional ones, so a geometric question is never answered two different ways,
// and exact ties are broken by symbolic perturbation along vertex normals.

import simd

/// Edge-face crossings (Manifold's `Intersections`). Forward: P edges through Q faces.
/// Reverse: P faces crossed by Q edges, still stored as (P index, Q index).
package struct BooleanIntersections: Sendable {
    /// (P index, Q index) pairs; the edge is a forward half-edge index.
    package var p1q2: [SIMD2<Int>] = []
    /// Signed crossing direction of each pair.
    package var x12: [Int] = []
    /// Crossing points.
    package var v12: [SIMD3<Double>] = []
}

// MARK: - shared.h helpers

@inline(__always)
func withSign(_ positive: Bool, _ value: Double) -> Double {
    positive ? value : -value
}

/// `p < q` with symbolic perturbation: on exact equality, `dir < 0` breaks the tie.
@inline(__always)
func shadows(_ p: Double, _ q: Double, _ dir: Double) -> Bool {
    p == q ? dir < 0 : p < q
}

/// (y, z) of segment aL-aR at `x`, measured from the nearer endpoint to limit rounding.
func interpolate(_ aL: SIMD3<Double>, _ aR: SIMD3<Double>, _ x: Double) -> SIMD2<Double> {
    let dxL = x - aL.x
    let dxR = x - aR.x
    assert(dxL * dxR <= 0, "Boolean manifold error: not in domain")
    let useL = abs(dxL) < abs(dxR)
    let dLR = aR - aL
    let lambda = (useL ? dxL : dxR) / dLR.x
    if !lambda.isFinite || !dLR.y.isFinite || !dLR.z.isFinite {
        return SIMD2(aL.y, aL.z)
    }
    return SIMD2(lambda * dLR.y + (useL ? aL.y : aR.y), lambda * dLR.z + (useL ? aL.z : aR.z))
}

/// Crossing of projected segments aL-aR and bL-bR over the same x interval, whose y gaps
/// bracket zero. Returns (x, y, a.z, b.z).
func intersect(_ aL: SIMD3<Double>, _ aR: SIMD3<Double>, _ bL: SIMD3<Double>, _ bR: SIMD3<Double>) -> SIMD4<Double> {
    let dyL = bL.y - aL.y
    let dyR = bR.y - aR.y
    assert(dyL * dyR <= 0, "Boolean manifold error: no intersection")
    let useL = abs(dyL) < abs(dyR)
    let dx = aR.x - aL.x
    var lambda = (useL ? dyL : dyR) / (dyL - dyR)
    if !lambda.isFinite {
        lambda = 0
    }
    let aDy = aR.y - aL.y
    let bDy = bR.y - bL.y
    let useA = abs(aDy) < abs(bDy)
    return SIMD4(
        lambda * dx + (useL ? aL.x : aR.x),
        lambda * (useA ? aDy : bDy) + (useL ? (useA ? aL.y : bL.y) : (useA ? aR.y : bR.y)),
        lambda * (aR.z - aL.z) + (useL ? aL.z : aR.z),
        lambda * (bR.z - bL.z) + (useL ? bL.z : bR.z)
    )
}

// MARK: - Kernels

private struct FaceEdge {
    var edge: Int
    var start: Int
    var end: Int
    var isForward: Bool
}

/// The three edges of a triangle, each referenced by its forward half-edge.
private func loadFaceEdges(_ mesh: BooleanMesh, _ triangle: Int) -> [FaceEdge] {
    (0..<3).map { i in
        let halfedge = 3 * triangle + i
        let start = mesh.halfedges[halfedge].startVert
        let end = mesh.halfedges[3 * triangle + (i + 1) % 3].startVert
        return start < end
            ? FaceEdge(edge: halfedge, start: start, end: end, isForward: true)
            : FaceEdge(edge: mesh.halfedges[halfedge].pairedHalfedge, start: end, end: start, isForward: false)
    }
}

/// Manifold's Kernel02/11/12 with their template flags as stored properties.
struct BooleanKernels {
    let inP: BooleanMesh
    let inQ: BooleanMesh
    let expandP: Bool

    /// Shadow01: does vertex a0 of A shadow edge b1 (b1s -> b1e) of B, in x then y.
    private func shadow01(_ a0: Int, _ b1: Int, _ b1s: Int, _ b1e: Int, _ inA: BooleanMesh, _ inB: BooleanMesh, forward: Bool) -> (Int, SIMD2<Double>) {
        let a0x = inA.vertPos[a0].x
        let b1sx = inB.vertPos[b1s].x
        let b1ex = inB.vertPos[b1e].x
        let a0xp = inA.vertNormal[a0].x
        let b1sxp = inB.vertNormal[b1s].x
        let b1exp = inB.vertNormal[b1e].x
        var s01 = forward
            ? (shadows(a0x, b1ex, withSign(expandP, a0xp) - b1exp) ? 1 : 0) - (shadows(a0x, b1sx, withSign(expandP, a0xp) - b1sxp) ? 1 : 0)
            : (shadows(b1sx, a0x, withSign(expandP, b1sxp) - a0xp) ? 1 : 0) - (shadows(b1ex, a0x, withSign(expandP, b1exp) - a0xp) ? 1 : 0)
        var yz01 = SIMD2<Double>(repeating: .nan)
        if s01 != 0 {
            yz01 = interpolate(inB.vertPos[b1s], inB.vertPos[b1e], inA.vertPos[a0].x)
            let b1pair = inB.halfedges[b1].pairedHalfedge
            let dir = inB.faceNormal[b1 / 3].y + inB.faceNormal[b1pair / 3].y
            if forward {
                if !shadows(inA.vertPos[a0].y, yz01.x, -dir) {
                    s01 = 0
                }
            } else if !shadows(yz01.x, inA.vertPos[a0].y, withSign(expandP, dir)) {
                s01 = 0
            }
        }
        return (s01, yz01)
    }

    /// Kernel11: edge p1 of P against edge q1 of Q, projected along z. Returns (s11, xyzz).
    func kernel11(_ p1: Int, _ p1s: Int, _ p1e: Int, _ q1: Int, _ q1s: Int, _ q1e: Int) -> (Int, SIMD4<Double>) {
        var s11 = 0
        var k = 0
        var pRL = [SIMD3<Double>](repeating: .zero, count: 2)
        var qRL = [SIMD3<Double>](repeating: .zero, count: 2)
        // Exactly one of left/right must shadow, so the crossing lies between them.
        var isShadowing = false
        for (i, p0) in [p1s, p1e].enumerated() {
            let (s01, yz01) = shadow01(p0, q1, q1s, q1e, inP, inQ, forward: true)
            if yz01.x.isFinite {
                s11 += s01 * (i == 0 ? -1 : 1)
                if k < 2, k == 0 || (s01 != 0) != isShadowing {
                    isShadowing = s01 != 0
                    pRL[k] = inP.vertPos[p0]
                    qRL[k] = SIMD3(pRL[k].x, yz01.x, yz01.y)
                    k += 1
                }
            }
        }
        for (i, q0) in [q1s, q1e].enumerated() {
            let (s10, yz10) = shadow01(q0, p1, p1s, p1e, inQ, inP, forward: false)
            if yz10.x.isFinite {
                s11 += s10 * (i == 0 ? -1 : 1)
                if k < 2, k == 0 || (s10 != 0) != isShadowing {
                    isShadowing = s10 != 0
                    qRL[k] = inQ.vertPos[q0]
                    pRL[k] = SIMD3(qRL[k].x, yz10.x, yz10.y)
                    k += 1
                }
            }
        }
        guard s11 != 0 else {
            return (0, SIMD4(repeating: .nan))
        }
        assert(k == 2, "Boolean manifold error: s11")
        let xyzz11 = intersect(pRL[0], pRL[1], qRL[0], qRL[1])
        let dirP = inP.faceNormal[p1 / 3].z + inP.faceNormal[inP.halfedges[p1].pairedHalfedge / 3].z
        let dirQ = inQ.faceNormal[q1 / 3].z + inQ.faceNormal[inQ.halfedges[q1].pairedHalfedge / 3].z
        if !shadows(xyzz11.z, xyzz11.w, withSign(expandP, dirP) - dirQ) {
            s11 = 0
        }
        return (s11, xyzz11)
    }

    /// Kernel02: vertex a0 of A against face b2 of B, along z. Returns (s02, z02).
    fileprivate func kernel02(_ a0: Int, _ b2: Int, _ edgeB: [FaceEdge], inA: BooleanMesh, inB: BooleanMesh, forward: Bool) -> (Int, Double) {
        var s02 = 0
        var k = 0
        var yzzRL = [SIMD3<Double>](repeating: .zero, count: 2)
        var isShadowing = false
        for i in 0..<3 {
            let (s01, yz01) = shadow01(a0, edgeB[i].edge, edgeB[i].start, edgeB[i].end, inA, inB, forward: forward)
            if yz01.x.isFinite {
                s02 += s01 * (forward == edgeB[i].isForward ? -1 : 1)
                if k < 2, k == 0 || (s01 != 0) != isShadowing {
                    isShadowing = s01 != 0
                    yzzRL[k] = SIMD3(yz01.x, yz01.y, yz01.y)
                    k += 1
                }
            }
        }
        guard s02 != 0 else {
            return (0, .nan)
        }
        assert(k == 2, "Boolean manifold error: s02")
        let vertPosA = inA.vertPos[a0]
        let z02 = interpolate(yzzRL[0], yzzRL[1], vertPosA.y).y
        if forward {
            if !shadows(vertPosA.z, z02, -inB.faceNormal[b2].z) {
                s02 = 0
            }
        } else if !shadows(z02, vertPosA.z, withSign(expandP, inB.faceNormal[b2].z)) {
            s02 = 0
        }
        return (s02, z02)
    }

    /// Kernel02 with the face edges loaded (used by winding numbers).
    func kernel02(_ a0: Int, _ b2: Int, forward: Bool) -> (Int, Double) {
        let inA = forward ? inP : inQ
        let inB = forward ? inQ : inP
        return kernel02(a0, b2, loadFaceEdges(inB, b2), inA: inA, inB: inB, forward: forward)
    }

    /// Kernel12: edge a1 of A against face b2 of B. Returns (x12, v12).
    func kernel12(_ a1: Int, _ b2: Int, forward: Bool) -> (Int, SIMD3<Double>) {
        let inA = forward ? inP : inQ
        let inB = forward ? inQ : inP
        var x12 = 0
        var k = 0
        var xzyLR0 = [SIMD3<Double>](repeating: .zero, count: 2)
        var xzyLR1 = [SIMD3<Double>](repeating: .zero, count: 2)
        var isShadowing = false
        let edgeAStart = inA.halfedges[a1].startVert
        let edgeAEnd = inA.halfedges[a1].endVert
        let edgeB = loadFaceEdges(inB, b2)

        for vertA in [edgeAStart, edgeAEnd] {
            let (s, z) = kernel02(vertA, b2, edgeB, inA: inA, inB: inB, forward: forward)
            if z.isFinite {
                x12 += s * ((vertA == edgeAStart) == forward ? 1 : -1)
                if k < 2, k == 0 || (s != 0) != isShadowing {
                    isShadowing = s != 0
                    let position = inA.vertPos[vertA]
                    xzyLR0[k] = SIMD3(position.x, position.z, position.y)
                    xzyLR1[k] = xzyLR0[k]
                    xzyLR1[k].y = z
                    k += 1
                }
            }
        }
        for i in 0..<3 {
            let (s, xyzz) = forward
                ? kernel11(a1, edgeAStart, edgeAEnd, edgeB[i].edge, edgeB[i].start, edgeB[i].end)
                : kernel11(edgeB[i].edge, edgeB[i].start, edgeB[i].end, a1, edgeAStart, edgeAEnd)
            if xyzz.x.isFinite {
                x12 -= s * (edgeB[i].isForward ? 1 : -1)
                if k < 2, k == 0 || (s != 0) != isShadowing {
                    isShadowing = s != 0
                    xzyLR0[k] = SIMD3(xyzz.x, xyzz.z, xyzz.y)
                    xzyLR1[k] = xzyLR0[k]
                    xzyLR1[k].y = xyzz.w
                    if !forward {
                        swap(&xzyLR0[k].y, &xzyLR1[k].y)
                    }
                    k += 1
                }
            }
        }
        guard x12 != 0 else {
            return (0, SIMD3(repeating: .nan))
        }
        assert(k == 2, "Boolean manifold error: v12")
        let xzyy = intersect(xzyLR0[0], xzyLR0[1], xzyLR1[0], xzyLR1[1])
        return (x12, SIMD3(xzyy.x, xzyy.z, xzyy.y))
    }

    /// Intersect12: every forward edge of A against the faces of B the collider returns,
    /// sorted by edge then face. Forward: A = P, B = Q.
    func intersect12(forward: Bool, colliderB: Collider) -> BooleanIntersections {
        let inA = forward ? inP : inQ
        var result = BooleanIntersections()
        for edge in inA.halfedges.indices {
            let start = inA.halfedges[edge].startVert
            let end = inA.halfedges[edge].endVert
            guard start < end else {
                continue
            }
            colliderB.forEachOverlap(BooleanBox(inA.vertPos[start], inA.vertPos[end])) { face in
                let (x12, v12) = kernel12(edge, face, forward: forward)
                if v12.x.isFinite {
                    result.p1q2.append(forward ? SIMD2(edge, face) : SIMD2(face, edge))
                    result.x12.append(x12)
                    result.v12.append(v12)
                }
            }
        }
        // Sort by the A index, then the B index.
        let primary = forward ? 0 : 1
        let order = result.p1q2.indices.sorted { a, b in
            let pa = result.p1q2[a]
            let pb = result.p1q2[b]
            return pa[primary] != pb[primary] ? pa[primary] < pb[primary] : pa[1 - primary] < pb[1 - primary]
        }
        result.p1q2 = order.map { result.p1q2[$0] }
        result.x12 = order.map { result.x12[$0] }
        result.v12 = order.map { result.v12[$0] }
        return result
    }
}
