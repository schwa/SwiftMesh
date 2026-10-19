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
            #expect(abs(cube.windingNumber(at: point, bvh: bvh) - 1) < 1e-4)
            #expect(cube.contains(point))
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
            #expect(abs(torus.windingNumber(at: point, bvh: bvh) - 1) < 1e-3)
            #expect(torus.contains(point))
        }
        for point: SIMD3<Float> in [.zero, [0, 0.2, 0], [0.6, 0, 0], [0.3, 0.3, 0]] {
            #expect(abs(torus.windingNumber(at: point, bvh: bvh)) < 1e-3)
            #expect(!torus.contains(point))
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

    @Test("Empty mesh is zero everywhere")
    func empty() {
        #expect(Mesh(positions: [], faces: [[Int]]()).windingNumber(at: .zero) == 0)
    }
}
