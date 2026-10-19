import simd
@testable import SwiftMesh
import Testing

@Suite("Generalized winding number")
struct WindingNumberTests {
    static let cubePositions: [SIMD3<Float>] = [
        [-0.5, -0.5, -0.5], [0.5, -0.5, -0.5], [0.5, 0.5, -0.5], [-0.5, 0.5, -0.5],
        [-0.5, -0.5, 0.5], [0.5, -0.5, 0.5], [0.5, 0.5, 0.5], [-0.5, 0.5, 0.5]
    ]
    static let cubeFaces: [[Int]] = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [3, 7, 6, 2], [1, 2, 6, 5], [0, 4, 7, 3]]

    @Test("Cube inside and outside")
    func cube() {
        let cube = Mesh.cube()
        let bvh = TriangleBVH(mesh: cube)
        for point: SIMD3<Float> in [.zero, [0.4, -0.3, 0.2], [-0.45, 0.45, -0.45]] {
            #expect(abs(cube.windingNumber(at: point) - 1) < 1e-4)
            #expect(abs(bvh.windingNumber(at: point, accuracy: 16) - 1) < 1e-3)
            #expect(cube.contains(point, bvh: bvh))
        }
        for point: SIMD3<Float> in [[2, 0, 0], [0.6, 0.6, 0.6], [-0.55, 0, 0], [10, -10, 3]] {
            #expect(abs(cube.windingNumber(at: point)) < 1e-4)
            #expect(!cube.contains(point, bvh: bvh))
        }
    }

    @Test("Torus inside, hole and outside")
    func torus() {
        let torus = Mesh.torus(majorRadius: 0.3, minorRadius: 0.15)
        let bvh = TriangleBVH(mesh: torus)
        for point: SIMD3<Float> in [[0.3, 0, 0], [0, 0, -0.3], [-0.38, 0.05, 0]] {
            #expect(abs(torus.windingNumber(at: point) - 1) < 1e-3)
            #expect(abs(bvh.windingNumber(at: point, accuracy: 16) - 1) < 1e-3)
            #expect(torus.contains(point, bvh: bvh))
        }
        for point: SIMD3<Float> in [.zero, [0, 0.2, 0], [0.6, 0, 0], [0.3, 0.3, 0]] {
            #expect(abs(torus.windingNumber(at: point)) < 1e-3)
            #expect(abs(bvh.windingNumber(at: point, accuracy: 16)) < 1e-3)
            #expect(!torus.contains(point, bvh: bvh))
        }
    }

    @Test("Cube with one face removed")
    func openCube() {
        // Drop the +Z face.
        let open = Mesh(positions: Self.cubePositions, faces: Self.cubeFaces.enumerated().filter { $0.offset != 1 }.map(\.element))
        #expect(abs(open.windingNumber(at: .zero) - 5.0 / 6.0) < 1e-4)
        for point: SIMD3<Float> in [.zero, [0.3, 0.3, -0.3], [0, 0, 0.2]] {
            #expect(open.contains(point))
        }
        for point: SIMD3<Float> in [[2, 0, 0], [0, 0, -1], [0, 0, 1]] {
            #expect(!open.contains(point))
        }
    }

    @Test("Inward-wound cube gives -1 inside")
    func reversed() {
        let inverted = Mesh(positions: Self.cubePositions, faces: Self.cubeFaces.map { $0.reversed() })
        #expect(abs(inverted.windingNumber(at: .zero) + 1) < 1e-4)
        #expect(!inverted.contains(.zero))
    }

    static let fastMeshes: [(String, Mesh)] = [
        ("cube", .cube()),
        ("torus", .torus()),
        ("sphere", .sphere()),
        ("open cube", Mesh(positions: cubePositions, faces: cubeFaces.enumerated().filter { $0.offset != 1 }.map(\.element)))
    ]

    @Test("Fast winding number matches the exact sum", arguments: fastMeshes.indices)
    func fastMatchesExact(meshIndex: Int) {
        let mesh = Self.fastMeshes[meshIndex].1
        let bvh = TriangleBVH(mesh: mesh)
        var generator = TriangleBVHTests.SplitMix64(state: 5)
        var worstDefault: Float = 0
        var worstAccurate: Float = 0
        for _ in 0..<300 {
            let point = TriangleBVHTests.randomPoint(&generator, range: -1...1)
            let exact = mesh.windingNumber(at: point)
            let fast = bvh.windingNumber(at: point)
            #expect((fast > 0.5) == (exact > 0.5), "misclassified \(point)")
            worstDefault = max(worstDefault, abs(fast - exact))
            worstAccurate = max(worstAccurate, abs(bvh.windingNumber(at: point, accuracy: 16) - exact))
        }
        let name = Self.fastMeshes[meshIndex].0
        #expect(worstDefault < 0.1, "\(name): worst error \(worstDefault) at default accuracy")
        #expect(worstAccurate < 1e-3, "\(name): worst error \(worstAccurate) at accuracy 16")
    }

    @Test("Fast winding number classifies like the exact one")
    func fastContains() {
        let torus = Mesh.torus()
        let bvh = TriangleBVH(mesh: torus)
        #expect(torus.contains([0.3, 0, 0], bvh: bvh))
        #expect(!torus.contains(.zero, bvh: bvh))
        #expect(TriangleBVH(triangles: []).windingNumber(at: .zero) == 0)
    }

    @Test("Empty mesh is zero everywhere")
    func empty() {
        #expect(Mesh(positions: [], faces: [[Int]]()).windingNumber(at: .zero) == 0)
    }
}
