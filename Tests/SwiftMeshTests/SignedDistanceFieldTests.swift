import simd
@testable import SwiftMesh
import Testing

@Suite("Signed distance field")
struct SignedDistanceFieldTests {
    @Test("Signed distance of single points")
    func singlePoints() throws {
        let cube = Mesh.cube()
        #expect(try abs(#require(cube.signedDistance(at: .zero)) + 0.5) < 1e-5)
        #expect(try abs(#require(cube.signedDistance(at: [0, 0, 0.4])) + 0.1) < 1e-5)
        #expect(try abs(#require(cube.signedDistance(at: [0, 2, 0])) - 1.5) < 1e-5)
        #expect(Mesh(positions: [], faces: [[Int]]()).signedDistance(at: .zero) == nil)
    }

    @Test("Grid layout is x fastest, with samples on the padded bounds")
    func layout() throws {
        let field = try #require(Mesh.cube().signedDistanceField(resolution: [3, 4, 5], padding: 0.25))
        #expect(field.values.count == 60)
        #expect(field.origin == [-0.75, -0.75, -0.75])
        #expect(simd_distance(field.position(x: 2, y: 3, z: 4), [0.75, 0.75, 0.75]) < 1e-6)
        #expect(field.index(x: 1, y: 0, z: 0) == 1)
        #expect(field.index(x: 0, y: 1, z: 0) == 3)
        #expect(field.index(x: 0, y: 0, z: 1) == 12)
        // The center sample (1, 2, 2) is not on the grid for even counts, so check a known inside sample instead.
        #expect(field[1, 1, 2] < 0)
    }

    @Test("Baked sphere matches the analytic signed distance within one cell")
    func sphere() throws {
        let field = try #require(Mesh.sphere().signedDistanceField(resolution: [24, 24, 24], padding: 0.2))
        let cell = field.spacing.max()
        for z in 0..<24 {
            for y in 0..<24 {
                for x in 0..<24 {
                    let expected = simd_length(field.position(x: x, y: y, z: z)) - 0.5
                    #expect(abs(field[x, y, z] - expected) < cell)
                }
            }
        }
    }

    @Test("Cube signs: negative inside, positive outside")
    func cubeSigns() throws {
        let field = try #require(Mesh.cube().signedDistanceField(resolution: [20, 20, 20], padding: 0.3))
        for z in 0..<20 {
            for y in 0..<20 {
                for x in 0..<20 {
                    let position = field.position(x: x, y: y, z: z)
                    let margin = 0.5 - simd_reduce_max(abs(position))
                    if abs(margin) > 1e-4 {
                        #expect((field[x, y, z] < 0) == (margin > 0), "sample \(position)")
                    }
                }
            }
        }
    }

    @Test("Flood-filled signs match a winding test at every sample")
    func floodFillMatchesExact() throws {
        let torus = Mesh.torus()
        let bvh = TriangleBVH(mesh: torus)
        let field = try #require(torus.signedDistanceField(resolution: [16, 12, 16], padding: 0.1, bvh: bvh))
        for z in 0..<16 {
            for y in 0..<12 {
                for x in 0..<16 {
                    let exact = try #require(torus.signedDistance(at: field.position(x: x, y: y, z: z), bvh: bvh))
                    #expect(field[x, y, z] == exact)
                }
            }
        }
    }

    @Test("Empty mesh bakes nothing")
    func empty() {
        #expect(Mesh(positions: [], faces: [[Int]]()).signedDistanceField(resolution: [2, 2, 2]) == nil)
    }
}
