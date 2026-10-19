import simd
@testable import SwiftMesh
import Testing

@Suite("Mesh closest point")
struct MeshClosestPointTests {
    static let cube = Mesh.cube()
    static let cubeBVH = TriangleBVH(mesh: cube)

    static func check(_ mesh: Mesh, _ bvh: TriangleBVH, from point: SIMD3<Float>, expected: SIMD3<Float>, distance: Float) throws {
        for candidate in [mesh.closestPoint(to: point), mesh.closestPoint(to: point, bvh: bvh)] {
            let result = try #require(candidate)
            #expect(simd_distance(result.point, expected) < 1e-5)
            #expect(abs(result.distance - distance) < 1e-5)
        }
    }

    @Test("Point near a cube face")
    func nearFace() throws {
        try Self.check(Self.cube, Self.cubeBVH, from: [0.1, 0.2, 2], expected: [0.1, 0.2, 0.5], distance: 1.5)
        let result = try #require(Self.cube.closestPoint(to: [0.1, 0.2, 2], bvh: Self.cubeBVH))
        #expect(simd_distance(result.normal, [0, 0, 1]) < 1e-6)
        #expect(simd_distance(Self.cube.faceNormal(result.face), [0, 0, 1]) < 1e-6)
    }

    @Test("Point inside a cube")
    func inside() throws {
        try Self.check(Self.cube, Self.cubeBVH, from: [0, 0, 0.4], expected: [0, 0, 0.5], distance: 0.1)
    }

    @Test("Point near a cube edge")
    func nearEdge() throws {
        try Self.check(Self.cube, Self.cubeBVH, from: [1, 1, 0.1], expected: [0.5, 0.5, 0.1], distance: Float(0.5).squareRoot())
    }

    @Test("Point near a cube vertex")
    func nearVertex() throws {
        try Self.check(Self.cube, Self.cubeBVH, from: [1, 1, 1], expected: [0.5, 0.5, 0.5], distance: Float(0.75).squareRoot())
    }

    @Test("Point on the surface")
    func onSurface() throws {
        try Self.check(Self.cube, Self.cubeBVH, from: [0.5, 0.3, -0.2], expected: [0.5, 0.3, -0.2], distance: 0)
    }

    @Test("Sphere: BVH matches brute force and the analytic distance")
    func sphere() throws {
        let sphere = Mesh.sphere()
        let bvh = TriangleBVH(mesh: sphere)
        var generator = TriangleBVHTests.SplitMix64(state: 4)
        for _ in 0..<300 {
            let point = TriangleBVHTests.randomPoint(&generator)
            let brute = try #require(sphere.closestPoint(to: point))
            let fast = try #require(sphere.closestPoint(to: point, bvh: bvh))
            #expect(abs(brute.distance - fast.distance) < 1e-5)
            // The closest point is not unique when several triangles tie, so check it lies at the reported distance.
            #expect(abs(simd_distance(fast.point, point) - fast.distance) < 1e-5)
            // Radius 0.5; the tessellation sits up to ~0.005 inside the true sphere.
            #expect(abs(fast.distance - abs(simd_length(point) - 0.5)) < 0.01)
            #expect(simd_dot(fast.normal, fast.point) > 0)
        }
    }

    @Test("Empty mesh has no closest point")
    func empty() {
        let mesh = Mesh(positions: [], faces: [[Int]]())
        #expect(mesh.closestPoint(to: .zero) == nil)
        #expect(mesh.distance(to: .zero, bvh: TriangleBVH(mesh: mesh)) == nil)
    }
}
