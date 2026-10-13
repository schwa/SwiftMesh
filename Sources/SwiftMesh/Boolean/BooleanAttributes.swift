// Ported from Manifold (https://github.com/elalish/manifold): src/boolean_result.cpp
// (CreateProperties, Barycentric), src/shared.h (GetBarycentric).
// Copyright 2021 The Manifold Authors. Licensed under the Apache License, Version 2.0; see NOTICE.

import simd

/// Manifold's `GetBarycentric`: weights of `v` in triangle `triangle`, snapping to exact 1
/// within `tolerance` of a vertex and exact 0 within `tolerance` of an edge.
func barycentric(_ v: SIMD3<Double>, _ triangle: [SIMD3<Double>], tolerance: Double) -> SIMD3<Double> {
    let edges = [triangle[2] - triangle[1], triangle[0] - triangle[2], triangle[1] - triangle[0]]
    let d2 = SIMD3(simd_dot(edges[0], edges[0]), simd_dot(edges[1], edges[1]), simd_dot(edges[2], edges[2]))
    let longSide = d2[0] > d2[1] && d2[0] > d2[2] ? 0 : (d2[1] > d2[2] ? 1 : 2)
    let crossP = simd_cross(edges[0], edges[1])
    let area2 = simd_dot(crossP, crossP)
    let tolerance2 = tolerance * tolerance

    for i in 0..<3 {
        let dv = v - triangle[i]
        if simd_dot(dv, dv) < tolerance2 {
            var uvw = SIMD3<Double>.zero
            uvw[i] = 1
            return uvw
        }
    }
    if d2[longSide] < tolerance2 {
        return SIMD3(1, 0, 0) // point
    }
    if area2 > d2[longSide] * tolerance2 {
        var uvw = SIMD3<Double>.zero
        for i in 0..<3 {
            let j = (i + 1) % 3
            let crossPv = simd_cross(edges[i], v - triangle[j])
            let area2v = simd_dot(crossPv, crossPv)
            uvw[i] = area2v < d2[i] * tolerance2 ? 0 : simd_dot(crossPv, crossP)
        }
        let sum = uvw.sum()
        return sum == 0 ? SIMD3(repeating: 1.0 / 3.0) : uvw / sum
    }
    // Line.
    let nextV = (longSide + 1) % 3
    let alpha = simd_dot(v - triangle[nextV], edges[longSide]) / d2[longSide]
    var uvw = SIMD3<Double>.zero
    uvw[nextV] = 1 - alpha
    uvw[(nextV + 1) % 3] = alpha
    return uvw
}

extension BooleanMesh {
    /// A `Mesh` whose corner attributes are interpolated from the Boolean's inputs
    /// (Manifold's `CreateProperties`).
    ///
    /// Each corner is located barycentrically in the input triangle its face came from
    /// (`triRef`), and that triangle's original `Mesh` corner values are blended. An attribute
    /// is kept only if both inputs have it. With `invertQ` (difference), normals from Q are
    /// negated so they point out of the result.
    ///
    /// - Parameters:
    ///   - p: The P input as converted for the Boolean (it carries its source attributes).
    ///   - q: The Q input.
    func toMesh(attributesFrom p: BooleanMesh, _ q: BooleanMesh, invertQ: Bool) -> Mesh {
        var mesh = toMesh()
        guard triRef.count == numTri else {
            return mesh
        }
        let sources = [p, q]
        // Blend over P's corners followed by Q's; Q's normals flip when Q is inverted.
        var attributesQ = q.sourceAttributes
        if invertQ {
            attributesQ.normals = attributesQ.normals?.map { -$0 }
        }
        let combined = CornerAttributes.concatenated([p.sourceAttributes, attributesQ])
        let offsets = [0, p.sourceAttributes.cornerCount]
        var blends: [[CornerAttributes.Weight]] = []
        blends.reserveCapacity(halfedges.count)
        for tri in 0..<numTri {
            let ref = triRef[tri]
            let input = sources[ref.x]
            let sourceTriangle = (0..<3).map { input.vertPos[input.halfedges[3 * ref.y + $0].startVert] }
            let corners = SIMD3(input.halfedges[3 * ref.y].sourceCorner, input.halfedges[3 * ref.y + 1].sourceCorner, input.halfedges[3 * ref.y + 2].sourceCorner)
            for corner in 0..<3 {
                let position = vertPos[halfedges[3 * tri + corner].startVert]
                let uvw = barycentric(position, sourceTriangle, tolerance: epsilon)
                blends.append((0..<3).filter { corners[$0] >= 0 }.map { (offsets[ref.x] + corners[$0], Float(uvw[$0])) })
            }
        }
        mesh.cornerAttributes = combined.blended(blends)
        return mesh
    }
}
