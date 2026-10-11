import simd

public extension Mesh {
    /// Split the mesh by a plane into the parts on the front (normal side) and back.
    ///
    /// Faces that straddle the plane are clipped. With `capped`, each part's open loops on
    /// the cut are closed with planar n-gon faces (nested loops become holes), so a closed
    /// input yields closed parts. Per-corner attributes are not preserved, and all
    /// submeshes are merged into one.
    ///
    /// - Parameters:
    ///   - normal: Plane normal. Need not be unit length.
    ///   - point: Any point on the plane.
    ///   - capped: Close each part's cut with planar faces.
    ///   - weldTolerance: Maximum distance for merging vertices created along the cut.
    func split(planeNormal normal: SIMD3<Float>, point: SIMD3<Float>, capped: Bool = true, weldTolerance: Float = 1e-5) -> (front: Mesh, back: Mesh) {
        let unitNormal = simd_normalize(normal)
        var front = TriangleSoup()
        var back = TriangleSoup()
        let soup = TriangleSoup(mesh: self)
        for triangle in soup.triangles {
            let corners = [soup.positions[triangle.0], soup.positions[triangle.1], soup.positions[triangle.2]]
            let distances = corners.map { simd_dot($0 - point, unitNormal) }
            var frontPolygon: [SIMD3<Float>] = []
            var backPolygon: [SIMD3<Float>] = []
            for index in 0..<3 {
                let next = (index + 1) % 3
                if distances[index] >= 0 {
                    frontPolygon.append(corners[index])
                }
                if distances[index] <= 0 {
                    backPolygon.append(corners[index])
                }
                if (distances[index] > 0 && distances[next] < 0) || (distances[index] < 0 && distances[next] > 0) {
                    let t = distances[index] / (distances[index] - distances[next])
                    let crossing = corners[index] + (corners[next] - corners[index]) * t
                    frontPolygon.append(crossing)
                    backPolygon.append(crossing)
                }
            }
            // A triangle lying in the plane goes to the side its normal faces.
            if distances.allSatisfy({ $0 == 0 }) {
                let faceNormal = simd_cross(corners[1] - corners[0], corners[2] - corners[0])
                if simd_dot(faceNormal, unitNormal) >= 0 {
                    backPolygon = []
                } else {
                    frontPolygon = []
                }
            }
            Self.appendFan(frontPolygon, to: &front)
            Self.appendFan(backPolygon, to: &back)
        }
        var frontMesh = front.toMesh(weldTolerance: weldTolerance)
        var backMesh = back.toMesh(weldTolerance: weldTolerance)
        if capped {
            frontMesh = frontMesh.cappingPlanarBoundaries(normal: unitNormal, point: point, tolerance: weldTolerance * 10)
            backMesh = backMesh.cappingPlanarBoundaries(normal: unitNormal, point: point, tolerance: weldTolerance * 10)
        }
        return (frontMesh, backMesh)
    }
}

private extension Mesh {
    static func appendFan(_ polygon: [SIMD3<Float>], to soup: inout TriangleSoup) {
        guard polygon.count >= 3 else {
            return
        }
        let base = soup.positions.count
        soup.positions += polygon
        for index in 1..<(polygon.count - 1) {
            soup.triangles.append((base, base + index, base + index + 1))
        }
    }

    /// Close boundary loops that lie in the plane with n-gon faces. Loops nested at odd depth become holes.
    func cappingPlanarBoundaries(normal: SIMD3<Float>, point: SIMD3<Float>, tolerance: Float) -> Mesh {
        let loops = topology.boundaryLoops().filter { loop in
            loop.allSatisfy { abs(simd_dot(positions[$0.raw] - point, normal)) <= tolerance }
        }
        guard !loops.isEmpty else {
            return self
        }
        let helper: SIMD3<Float> = abs(normal.x) < 0.9 ? [1, 0, 0] : [0, 1, 0]
        let u = simd_normalize(simd_cross(helper, normal))
        let v = simd_cross(normal, u)
        let flat = loops.map { loop in loop.map { SIMD2(simd_dot(positions[$0.raw], u), simd_dot(positions[$0.raw], v)) } }

        func contains(_ polygon: [SIMD2<Float>], _ test: SIMD2<Float>) -> Bool {
            var inside = false
            var previous = polygon.count - 1
            for index in polygon.indices {
                let a = polygon[index]
                let b = polygon[previous]
                if (a.y > test.y) != (b.y > test.y), test.x < (b.x - a.x) * (test.y - a.y) / (b.y - a.y) + a.x {
                    inside.toggle()
                }
                previous = index
            }
            return inside
        }

        let containers = loops.indices.map { index in
            loops.indices.filter { $0 != index && contains(flat[$0], flat[index][0]) }
        }
        // Boundary loops run opposite to the missing cap, so each cap loop is reversed.
        var definitions = topology.faces.filter { $0.edge != nil }.map { face in
            HalfEdgeTopology.FaceDefinition(outer: topology.vertexLoop(for: face.id).map(\.raw), holes: topology.holeVertexLoops(for: face.id).map { $0.map(\.raw) })
        }
        for index in loops.indices where containers[index].count.isMultiple(of: 2) {
            let holes = loops.indices.filter { hole in
                containers[hole].count == containers[index].count + 1 && containers[hole].contains(index)
            }
            definitions.append(.init(outer: loops[index].reversed().map(\.raw), holes: holes.map { loops[$0].reversed().map(\.raw) }))
        }
        return Mesh(positions: positions, faces: definitions)
    }
}
