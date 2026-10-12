import simd
@testable import SwiftMesh
import Testing

@Suite("Boolean winding numbers")
struct WindingTests {
    private func grid(_ count: Int, extent: Float) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        // Offsets keep points away from the exact symmetry planes of the test shapes.
        for x in 0..<count { for y in 0..<count { for z in 0..<count {
            let unit = SIMD3(Float(x), Float(y), Float(z)) / Float(count - 1) - 0.5
            points.append(unit * 2 * extent + [0.0137, 0.0071, 0.0029])
        } } }
        return points
    }

    @Test("Point winding inside/outside an icosphere matches distance from the center")
    func sphere() throws {
        let mesh = Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 3, attributes: [])
        let points = grid(9, extent: 0.7)
        let winding = try #require(mesh.windingNumbers(at: points))
        for (point, value) in zip(points, winding) {
            let radius = simd_length(point)
            // Skip the thin band where the faceted sphere and the true sphere disagree.
            if radius < 0.47 {
                #expect(value == 1, "\(point)")
            } else if radius > 0.51 {
                #expect(value == 0, "\(point)")
            }
        }
    }

    @Test("Torus hole is outside")
    func torus() throws {
        let torus = Mesh.torus(majorSegments: 48, minorSegments: 24, majorRadius: 0.3, minorRadius: 0.1, attributes: [])
        // The torus lies in the xz plane around the y axis.
        let winding = try #require(torus.windingNumbers(at: [[0, 0, 0], [0.3, 0.001, 0.001], [0.0011, 0.0013, 0.31], [0.5, 0, 0]]))
        #expect(winding == [0, 1, 1, 0])
    }

    @Test("Nested shells add up")
    func nested() throws {
        let outer = Mesh.icoSphere(extents: [2, 2, 2], subdivisions: 2, attributes: [])
        let inner = Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 2, attributes: [])
        let both = Mesh.merged([outer, inner])
        let winding = try #require(both.windingNumbers(at: [[0.01, 0.02, 0.03], [0.7, 0.01, 0.02], [2, 0, 0]]))
        #expect(winding == [2, 1, 0])
    }

    @Test("Points exactly on the surface get a definite 0 or 1")
    func onSurface() throws {
        let cube = Mesh.cube(attributes: [])
        let corners: [SIMD3<Float>] = [[0.5, 0.5, 0.5], [0, 0, 0.5], [0.5, 0, 0], [-0.5, 0.1, 0.2]]
        let winding = try #require(cube.windingNumbers(at: corners))
        #expect(winding.allSatisfy { $0 == 0 || $0 == 1 })
    }

    @Test("Non-manifold meshes return nil")
    func open() {
        #expect(Mesh.quad(attributes: []).windingNumbers(at: [.zero]) == nil)
    }

    @Test("Winding03 marks the vertices of P inside Q, per component", arguments: [true, false])
    func winding03(expandP: Bool) throws {
        let q = try BooleanMesh(mesh: .icoSphere(extents: [1, 1, 1], subdivisions: 3, attributes: []))
        let rotation = simd_float4x4(simd_quatf(angle: 0.5, axis: simd_normalize([1, 1, 2])))
        let p = try BooleanMesh(mesh: Mesh.icoSphere(extents: [0.8, 0.8, 0.8], subdivisions: 2, attributes: []).transformed(by: rotation).translated(by: [0.31, 0.04, 0.02]))
        let kernels = BooleanKernels(inP: p, inQ: q, expandP: expandP)
        let forward = kernels.intersect12(forward: true, colliderB: q.makeFaceCollider())
        let w03 = kernels.winding03(forward: true, p1q2: forward.p1q2, colliderB: q.makeFaceCollider())
        // Each vertex agrees with an independent point query, away from the surface.
        let reference = q.pointWinding(p.vertPos)
        for (index, position) in p.vertPos.enumerated() where abs(simd_length(position) - 0.5) > 0.02 {
            #expect(w03[index] == reference[index])
        }
        #expect(w03.contains(1))
        #expect(w03.contains(0))

        // Reverse: Q's vertices relative to P.
        let reverse = kernels.intersect12(forward: false, colliderB: p.makeFaceCollider())
        let w30 = kernels.winding03(forward: false, p1q2: reverse.p1q2, colliderB: p.makeFaceCollider())
        let reverseReference = p.pointWinding(q.vertPos)
        for index in q.vertPos.indices {
            #expect(w30[index] == reverseReference[index])
        }
    }
}
