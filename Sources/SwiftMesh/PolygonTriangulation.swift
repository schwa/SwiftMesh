import simd

/// Triangulates a 2D polygon with optional holes.
///
/// Any winding is accepted: the outer contour is made counter-clockwise and holes clockwise.
/// Indices refer to the concatenation of `outer` followed by each hole in order.
///
/// - Parameter epsilon: The input's uncertainty. `nil` derives it from the bounding-box scale.
/// - Returns: Counter-clockwise triangles as indices into the flattened input.
public func triangulatePolygon(outer: [SIMD2<Double>], holes: [[SIMD2<Double>]] = [], epsilon: Double? = nil) -> [SIMD3<Int>] {
    guard outer.count >= 3 else {
        return []
    }
    var polygons: [[PolyVert]] = []
    var offset = 0
    for (contourIndex, contour) in ([outer] + holes).enumerated() {
        var polygon = contour.enumerated().map { PolyVert(pos: $0.element, idx: offset + $0.offset) }
        offset += contour.count
        guard contour.count >= 3 else {
            continue
        }
        let wantCounterClockwise = contourIndex == 0
        if (signedArea(contour) > 0) != wantCounterClockwise {
            polygon.reverse()
        }
        polygons.append(polygon)
    }
    return triangulate(polygons, epsilon: epsilon ?? -1)
}

/// Single-precision convenience for ``triangulatePolygon(outer:holes:epsilon:)``.
public func triangulatePolygon(outer: [SIMD2<Float>], holes: [[SIMD2<Float>]] = [], epsilon: Double? = nil) -> [SIMD3<Int>] {
    triangulatePolygon(outer: outer.map(SIMD2<Double>.init), holes: holes.map { $0.map(SIMD2<Double>.init) }, epsilon: epsilon)
}

/// Triangulates a planar (or nearly planar) 3D polygon with optional holes.
///
/// The polygon is projected onto the axis plane closest to its Newell normal. Triangles wind
/// counter-clockwise around that normal. Indices are as for ``triangulatePolygon(outer:holes:epsilon:)``.
public func triangulatePolygon(outer: [SIMD3<Double>], holes: [[SIMD3<Double>]] = [], epsilon: Double? = nil) -> [SIMD3<Int>] {
    let project = axisAlignedProjection(newellNormal(outer))
    return triangulatePolygon(outer: outer.map(project), holes: holes.map { $0.map(project) }, epsilon: epsilon)
}

/// Single-precision convenience for ``triangulatePolygon(outer:holes:epsilon:)``.
public func triangulatePolygon(outer: [SIMD3<Float>], holes: [[SIMD3<Float>]] = [], epsilon: Double? = nil) -> [SIMD3<Int>] {
    triangulatePolygon(outer: outer.map(SIMD3<Double>.init), holes: holes.map { $0.map(SIMD3<Double>.init) }, epsilon: epsilon)
}

private func signedArea(_ contour: [SIMD2<Double>]) -> Double {
    var area = 0.0
    for index in contour.indices {
        let current = contour[index]
        let next = contour[(index + 1) % contour.count]
        area += current.x * next.y - next.x * current.y
    }
    return area / 2
}

private func newellNormal(_ points: [SIMD3<Double>]) -> SIMD3<Double> {
    var normal = SIMD3<Double>.zero
    for index in points.indices {
        let current = points[index]
        let next = points[(index + 1) % points.count]
        normal.x += (current.y - next.y) * (current.z + next.z)
        normal.y += (current.z - next.z) * (current.x + next.x)
        normal.z += (current.x - next.x) * (current.y + next.y)
    }
    return normal
}
