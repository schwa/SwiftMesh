import Foundation
import GeometryLite3D
import simd
@testable import SwiftMesh
import Testing

@Suite("TriangleBVH")
struct TriangleBVHTests {
    struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static func randomPoint(_ generator: inout SplitMix64, range: ClosedRange<Float> = -1.5...1.5) -> SIMD3<Float> {
        [Float.random(in: range, using: &generator), Float.random(in: range, using: &generator), Float.random(in: range, using: &generator)]
    }

    static func bruteForceClosest(_ bvh: TriangleBVH, _ point: SIMD3<Float>) -> Float {
        bvh.triangles.map { simd_distance(closestPoint(onTriangle: $0.a, $0.b, $0.c, to: point).point, point) }.min() ?? .infinity
    }

    static func bruteForceRay(_ bvh: TriangleBVH, _ ray: Ray3D) -> Float? {
        bvh.triangles.compactMap { ray.intersect(triangle: $0.a, $0.b, $0.c)?.distance }.min()
    }

    static let meshes: [(String, Mesh)] = [
        ("cube", .cube()),
        ("sphere", .sphere()),
        ("torus", .torus())
    ]

    @Test("Empty mesh has no results")
    func empty() {
        let bvh = TriangleBVH(triangles: [])
        #expect(bvh.closestPoint(to: .zero) == nil)
        #expect(bvh.intersect(ray: Ray3D(origin: .zero, direction: [0, 0, 1])) == nil)
    }

    @Test("Keeps every triangle and its source face")
    func triangleCount() {
        let cube = Mesh.cube()
        let bvh = TriangleBVH(mesh: cube)
        #expect(bvh.triangles.count == 12)
        #expect(Set(bvh.triangles.map(\.face)) == Set(cube.topology.faces.map(\.id)))
    }

    @Test("Closest point matches brute force", arguments: meshes.indices)
    func closestPointMatchesBruteForce(meshIndex: Int) throws {
        let bvh = TriangleBVH(mesh: Self.meshes[meshIndex].1)
        var generator = SplitMix64(state: 1)
        for _ in 0..<500 {
            let point = Self.randomPoint(&generator)
            let result = try #require(bvh.closestPoint(to: point))
            #expect(abs(result.distance - Self.bruteForceClosest(bvh, point)) < 1e-5)
            #expect(abs(simd_distance(result.point, point) - result.distance) < 1e-5)
            let triangle = bvh.triangles[result.triangle]
            let fromBarycentrics = triangle.a * result.barycentrics.x + triangle.b * result.barycentrics.y + triangle.c * result.barycentrics.z
            #expect(simd_distance(fromBarycentrics, result.point) < 1e-5)
        }
    }

    @Test("Ray hits match brute force", arguments: meshes.indices)
    func rayMatchesBruteForce(meshIndex: Int) {
        let bvh = TriangleBVH(mesh: Self.meshes[meshIndex].1)
        var generator = SplitMix64(state: 2)
        var hits = 0
        for _ in 0..<500 {
            let origin = Self.randomPoint(&generator, range: -2...2)
            let target = Self.randomPoint(&generator, range: -0.4...0.4)
            let ray = Ray3D(origin: origin, direction: target - origin)
            let expected = Self.bruteForceRay(bvh, ray)
            let result = bvh.intersect(ray: ray)
            #expect((result == nil) == (expected == nil))
            if let result, let expected {
                hits += 1
                #expect(abs(result.distance - expected) < 1e-5)
            }
        }
        #expect(hits > 100)
    }

    @Test("Axis-aligned rays through a cube")
    func axisAlignedRays() throws {
        let bvh = TriangleBVH(mesh: .cube())
        let hit = try #require(bvh.intersect(ray: Ray3D(origin: [0, 0, 5], direction: [0, 0, -1])))
        #expect(abs(hit.distance - 4.5) < 1e-6)
        #expect(bvh.intersect(ray: Ray3D(origin: [0, 0, 5], direction: [0, 0, 1])) == nil)
        // Ray in a box face plane: the node slab test sees 0 * infinity.
        let grazingRay = Ray3D(origin: [0.5, 0, 5], direction: [0, 0, -1])
        #expect(bvh.intersect(ray: grazingRay)?.distance == Self.bruteForceRay(bvh, grazingRay))
    }

    @Test("Faster than brute force on a large mesh")
    func fasterThanBruteForce() {
        let bvh = TriangleBVH(mesh: .sphere(latitudeSegments: 64, longitudeSegments: 128))
        var generator = SplitMix64(state: 3)
        let points = (0..<200).map { _ in Self.randomPoint(&generator) }
        let clock = ContinuousClock()
        var sink: Float = 0
        let bvhTime = clock.measure {
            for point in points {
                sink += bvh.closestPoint(to: point)?.distance ?? 0
            }
        }
        let bruteTime = clock.measure {
            for point in points {
                sink += Self.bruteForceClosest(bvh, point)
            }
        }
        #expect(sink.isFinite)
        #expect(bvhTime * 10 < bruteTime, "BVH \(bvhTime), brute force \(bruteTime)")
    }
}
