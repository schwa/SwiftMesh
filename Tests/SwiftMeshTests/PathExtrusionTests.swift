import simd
@testable import SwiftMesh
import SwiftUI
import Testing

@Suite("Path extrusion")
struct PathExtrusionTests {
    @Test("Rectangle extrudes to a closed box with outward faces")
    func rectangle() {
        let mesh = Mesh.extruded(Path(CGRect(x: 0, y: 0, width: 2, height: 1)), depth: 0.5, attributes: [])
        #expect(mesh.faceCount == 6)
        #expect(mesh.validate().isEmpty)
        #expect(mesh.isManifold)
        #expect(mesh.bounds.min == [0, -1, 0])
        #expect(mesh.bounds.max == [2, 0, 0.5])
        let center = mesh.center
        for face in mesh.topology.faces {
            #expect(simd_dot(mesh.faceNormal(face.id), mesh.faceCentroid(face.id) - center) > 0)
        }
    }

    @Test("Nested subpath becomes a hole regardless of its winding", arguments: [false, true])
    func hole(reverseInner: Bool) {
        var path = Path(CGRect(x: 0, y: 0, width: 4, height: 4))
        var inner = Path(CGRect(x: 1, y: 1, width: 2, height: 2))
        if reverseInner {
            inner = Path { $0.addLines([CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 3), CGPoint(x: 3, y: 3), CGPoint(x: 3, y: 1)]); $0.closeSubpath() }
        }
        path.addPath(inner)
        let mesh = Mesh.extruded(path, depth: 1, attributes: [])
        #expect(mesh.validate().isEmpty)
        #expect(mesh.isManifold)
        #expect(mesh.topology.faces.filter { !$0.holeEdges.isEmpty }.count == 2)
        let holeRings = mesh.topology.faces.reduce(0) { $0 + $1.holeEdges.count }
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount - holeRings == 0) // genus 1
    }

    @Test("Walls only: no caps, one open band per outline")
    func wallsOnly() {
        var path = Path(CGRect(x: 0, y: 0, width: 4, height: 4))
        path.addPath(Path(CGRect(x: 1, y: 1, width: 2, height: 2)))
        let mesh = Mesh.extruded(path, depth: 1, mode: .wallsOnly, attributes: [])
        #expect(mesh.faceCount == 8)
        #expect(mesh.validate().isEmpty)
        #expect(mesh.topology.boundaryLoopCount == 4) // top and bottom rim of each band
        #expect(mesh.topology.faces.allSatisfy { abs(mesh.faceNormal($0.id).z) < 1e-6 })
    }

    @Test("Thin walls on a rectangle: closed genus-1 ring with the expected inner size")
    func thinWalls() {
        let mesh = Mesh.extruded(Path(CGRect(x: 0, y: 0, width: 4, height: 2)), depth: 1, mode: .thinWalls(thickness: 0.5), attributes: [])
        #expect(mesh.validate().isEmpty)
        #expect(mesh.isManifold)
        #expect(!mesh.topology.hasInconsistentFaceWinding)
        #expect(mesh.topology.surfaceComponents().map(\.genus) == [1])
        // Inner vertices form a 3 x 1 rectangle inset by 0.5 (y is flipped: 0...-2).
        let inner = mesh.positions.filter { $0.x > 0.01 && $0.x < 3.99 }
        #expect(Set(inner.map { [$0.x, $0.y] }) == [[0.5, -0.5], [3.5, -0.5], [3.5, -1.5], [0.5, -1.5]])
        // Faces point away from the wall material.
        let center = SIMD3<Float>(2, -1, 0.5)
        let outward = mesh.topology.faces.filter { face in
            let normal = mesh.faceNormal(face.id)
            let centroid = mesh.faceCentroid(face.id)
            if abs(normal.z) > 0.99 { return true } // caps
            let isOuterWall = centroid.x < 0.01 || centroid.x > 3.99 || centroid.y > -0.01 || centroid.y < -1.99
            let away = simd_dot(normal, centroid - center)
            return isOuterWall ? away > 0 : away < 0
        }
        #expect(outward.count == mesh.faceCount)
    }

    @Test("Thin walls keep holes: a frame becomes two concentric rings")
    func thinWallsWithHole() {
        var path = Path(CGRect(x: 0, y: 0, width: 4, height: 4))
        path.addPath(Path(CGRect(x: 1, y: 1, width: 2, height: 2)))
        let mesh = Mesh.extruded(path, depth: 1, mode: .thinWalls(thickness: 0.2), attributes: [])
        #expect(mesh.isManifold)
        #expect(mesh.topology.surfaceComponents().map(\.genus) == [1, 1])
        // The hole's wall grows outward into the material: its outer edge is at 0.8 and 3.2.
        #expect(mesh.positions.contains { abs($0.x - 0.8) < 1e-5 && abs($0.y + 0.8) < 1e-5 })
    }

    // MARK: - Thin walls on hard shapes (#121)

    private func volume(_ mesh: Mesh) -> Double {
        let triangles = mesh.triangulated()
        return triangles.topology.faces.reduce(0) { total, face in
            let v = triangles.topology.vertexLoop(for: face.id).map { SIMD3<Double>(triangles.positions[$0.raw]) }
            return total + simd_dot(v[0], simd_cross(v[1], v[2])) / 6
        }
    }

    private func polygonPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }

    /// The wall is a closed manifold inside the solid's volume and footprint (no miter spikes).
    private func expectWallInsideSolid(_ path: Path, thickness: Float) -> (wall: Double, solid: Double) {
        let mesh = Mesh.extruded(path, depth: 1, mode: .thinWalls(thickness: thickness), attributes: [])
        // Sample the footprint at mid-depth: points well within `thickness` of the outline are
        // wall, points beyond 2x thickness (the miter limit) are not.
        let outline = Mesh.flattenedLoops(path.cgPath, curveSegments: 8)
        let triangles = mesh.triangulated()
        let allPoints = outline.flatMap(\.self)
        let bounds = (min: allPoints.reduce(SIMD2<Float>(repeating: .infinity)) { simd_min($0, $1) }, max: allPoints.reduce(SIMD2<Float>(repeating: -.infinity)) { simd_max($0, $1) })
        var wrong = 0
        for row in 0..<60 {
            for column in 0..<60 {
                let point = bounds.min + (bounds.max - bounds.min) * SIMD2(Float(column) + 0.37, Float(row) + 0.61) / 60
                // Even-odd parity across loops, not `contains`.
                // swiftlint:disable:next reduce_boolean
                guard outline.reduce(false, { $0 != Mesh.contains($1, point) }) else {
                    continue
                }
                let distance = outline.flatMap { loop in
                    loop.indices.map { index -> Float in
                        let a = loop[index], b = loop[(index + 1) % loop.count]
                        let t = simd_clamp(simd_dot(point - a, b - a) / simd_length_squared(b - a), 0, 1)
                        return simd_distance(point, a + (b - a) * t)
                    }
                }.min() ?? 0
                let isWall = isInside(triangles, SIMD3(point.x, point.y, 0.5))
                if (distance < thickness * 0.95 && !isWall) || (distance > thickness * 2.05 && isWall) {
                    wrong += 1
                }
            }
        }
        #expect(wrong == 0)
        let solid = Mesh.extruded(path, depth: 1, attributes: [])
        #expect(mesh.isManifold)
        #expect(mesh.validate().isEmpty)
        #expect(!mesh.topology.hasInconsistentFaceWinding)
        let inside = solid.intersection(mesh, mergeCoplanar: false)
        let wallVolume = volume(mesh)
        // Intersecting with the solid removes nothing: the wall lies entirely inside it.
        #expect(abs(volume(inside) - wallVolume) < 1e-4)
        #expect(wallVolume > 0)
        return (wallVolume, volume(solid))
    }

    /// Parity of hits along a slightly skewed +x ray against a closed triangle mesh.
    private func isInside(_ mesh: Mesh, _ origin: SIMD3<Float>) -> Bool {
        let direction = simd_normalize(SIMD3<Float>(1, 0.000123, 0.000457))
        var hits = 0
        for face in mesh.topology.faces {
            let v = mesh.topology.vertexLoop(for: face.id).map { mesh.positions[$0.raw] }
            let edge1 = v[1] - v[0], edge2 = v[2] - v[0]
            let p = simd_cross(direction, edge2)
            let determinant = simd_dot(edge1, p)
            guard abs(determinant) > 1e-12 else { continue }
            let s = origin - v[0]
            let u = simd_dot(s, p) / determinant
            let q = simd_cross(s, edge1)
            let w = simd_dot(direction, q) / determinant
            if u >= 0, w >= 0, u + w <= 1, simd_dot(edge2, q) / determinant > 0 {
                hits += 1
            }
        }
        return !hits.isMultiple(of: 2)
    }

    @Test("Star with sharp tips: walls stay inside the solid")
    func thinWallsStar() {
        let points = (0..<10).map { index -> CGPoint in
            let angle = Double(index) / 10 * 2 * .pi
            let radius = index.isMultiple(of: 2) ? 2.0 : 0.5
            return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
        }
        let (wall, solid) = expectWallInsideSolid(polygonPath(points), thickness: 0.25)
        #expect(wall < solid)
    }

    @Test("V notch narrower than the wall: walls stay inside the solid")
    func thinWallsNotch() {
        let points: [CGPoint] = [.init(x: 0, y: 0), .init(x: 4, y: 0), .init(x: 4, y: 4), .init(x: 2.2, y: 4), .init(x: 2, y: 1), .init(x: 1.8, y: 4), .init(x: 0, y: 4)]
        let (wall, solid) = expectWallInsideSolid(polygonPath(points), thickness: 0.5)
        #expect(wall < solid)
    }

    @Test("Arms thinner than twice the wall fill completely instead of folding")
    func thinWallsThinFeature() {
        // L shape with arms 2 wide; thickness 1.1 erodes everything.
        let points: [CGPoint] = [.init(x: 0, y: 0), .init(x: 4, y: 0), .init(x: 4, y: 2), .init(x: 2, y: 2), .init(x: 2, y: 4), .init(x: 0, y: 4)]
        let (wall, solid) = expectWallInsideSolid(polygonPath(points), thickness: 1.1)
        #expect(abs(wall - solid) < 1e-4)
        #expect(abs(solid - 12) < 1e-4)
    }

    @Test("L shape wall volume matches the exact inset on both the miter and CSG paths")
    func thinWallsLShapeVolume() {
        let points: [CGPoint] = [.init(x: 0, y: 0), .init(x: 4, y: 0), .init(x: 4, y: 2), .init(x: 2, y: 2), .init(x: 2, y: 4), .init(x: 0, y: 4)]
        // Inset by 0.5 leaves an L of area 5: wall area 12 - 5.
        let fast = Mesh.extruded(polygonPath(points), depth: 1, mode: .thinWalls(thickness: 0.5), attributes: [])
        #expect(abs(volume(fast) - 7) < 1e-4)
        let loops = Mesh.flattenedLoops(polygonPath(points).cgPath, curveSegments: 8).map { Mesh.signedArea($0) < 0 ? Array($0.reversed()) : $0 }
        let robust = Mesh.robustThinWalls(loops, solid: Mesh.extruded(polygonPath(points), depth: 1, attributes: []), depth: 1, thickness: 0.5)
        #expect(robust.isManifold)
        #expect(abs(volume(robust) - 7) < 1e-4)
    }

    @Test("Curved path with attributes stays closed and triangulates")
    func circle() {
        let mesh = Mesh.extruded(Path(ellipseIn: CGRect(x: 0, y: 0, width: 2, height: 2)), depth: 1, curveSegments: 6)
        #expect(mesh.isManifold)
        #expect(mesh.validate().isEmpty)
        #expect(mesh.triangulated().isManifold)
    }
}
