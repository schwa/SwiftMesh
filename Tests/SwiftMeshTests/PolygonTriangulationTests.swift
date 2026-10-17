import simd
import SwiftMesh
import Testing

@Suite("Public polygon triangulation")
struct PolygonTriangulationTests {
    static func area(_ triangles: [SIMD3<Int>], _ points: [SIMD2<Double>]) -> Double {
        triangles.reduce(0) { sum, triangle in
            let a = points[triangle.x], b = points[triangle.y], c = points[triangle.z]
            let ab = b - a, ac = c - a
            return sum + (ab.x * ac.y - ab.y * ac.x) / 2
        }
    }

    @Test func convexSquare() {
        let square: [SIMD2<Double>] = [[0, 0], [1, 0], [1, 1], [0, 1]]
        let triangles = triangulatePolygon(outer: square)
        #expect(triangles.count == 2)
        #expect(abs(Self.area(triangles, square) - 1) < 1e-12)
    }

    @Test func clockwiseInputIsAccepted() {
        let square: [SIMD2<Double>] = [[0, 0], [0, 1], [1, 1], [1, 0]]
        let triangles = triangulatePolygon(outer: square)
        #expect(triangles.count == 2)
        #expect(abs(Self.area(triangles, square) - 1) < 1e-12)
    }

    @Test func concaveStar() {
        let star: [SIMD2<Double>] = (0..<10).map { index in
            let angle = Double(index) * .pi / 5
            let radius: Double = index.isMultiple(of: 2) ? 1 : 0.4
            return SIMD2(cos(angle), sin(angle)) * radius
        }
        let triangles = triangulatePolygon(outer: star)
        #expect(triangles.count == 8)
        #expect(Self.area(triangles, star) > 0)
    }

    @Test func squareWithHole() {
        let outer: [SIMD2<Double>] = [[0, 0], [4, 0], [4, 4], [0, 4]]
        // Same winding as the outer contour; it must be treated as a hole anyway.
        let hole: [SIMD2<Double>] = [[1, 1], [3, 1], [3, 3], [1, 3]]
        let triangles = triangulatePolygon(outer: outer, holes: [hole])
        #expect(triangles.count == 8)
        #expect(abs(Self.area(triangles, outer + hole) - 12) < 1e-9)
    }

    @Test func degenerateInput() {
        #expect(triangulatePolygon(outer: [SIMD2<Double>]()).isEmpty)
        #expect(triangulatePolygon(outer: [SIMD2<Double>(0, 0), [1, 1]]).isEmpty)
        let collinear: [SIMD2<Double>] = [[0, 0], [1, 0], [2, 0]]
        #expect(Self.area(triangulatePolygon(outer: collinear), collinear) == 0)
    }

    @Test(arguments: [SIMD3<Float>(1, 0, 0), [0, 1, 0], [0, 0, 1], [0, 0, -1]])
    func planar3D(normal: SIMD3<Float>) {
        // A square in the plane perpendicular to `normal`, wound CCW around it.
        let u = abs(normal.x) > 0.5 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        let v = simd_cross(normal, u)
        let square = [SIMD3<Float>.zero, u, u + v, v]
        let triangles = triangulatePolygon(outer: square)
        #expect(triangles.count == 2)
        for triangle in triangles {
            let a = square[triangle.x], b = square[triangle.y], c = square[triangle.z]
            #expect(simd_dot(simd_cross(b - a, c - a), normal) > 0)
        }
    }
}
