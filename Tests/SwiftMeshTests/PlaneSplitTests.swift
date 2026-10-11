import simd
@testable import SwiftMesh
import Testing

@Suite("Plane split")
struct PlaneSplitTests {
    private let normal = simd_normalize(SIMD3<Float>(1, 2, 0.5))
    private let point = SIMD3<Float>(0.1, 0, 0)

    private func signedDistances(_ mesh: Mesh) -> [Float] {
        mesh.positions.map { simd_dot($0 - point, normal) }
    }

    @Test("Capped split yields two closed halves on the correct sides")
    func capped() {
        let sphere = Mesh.icoSphere(subdivisions: 2, attributes: [])
        let (front, back) = sphere.split(planeNormal: normal, point: point)
        #expect(front.faceCount > 0)
        #expect(back.faceCount > 0)
        #expect(signedDistances(front).allSatisfy { $0 >= -1e-4 })
        #expect(signedDistances(back).allSatisfy { $0 <= 1e-4 })
        #expect(front.topology.boundaryLoopCount == 0)
        #expect(back.topology.boundaryLoopCount == 0)
        #expect(front.validate().isEmpty)
        #expect(front.isManifold)
        #expect(back.isManifold)
    }

    // The torus axis is y: cutting across it gives an annulus (cap with a hole); along it, two separate discs.
    @Test("Capping a torus cut handles nested and separate loops", arguments: [(SIMD3<Float>(0, 1, 0), true), (SIMD3<Float>(1, 0, 0), false), (SIMD3<Float>(0, 0, 1), false)])
    func torusCap(axis: SIMD3<Float>, expectHole: Bool) {
        let torus = Mesh.torus(attributes: [])
        let (open, _) = torus.split(planeNormal: axis, point: .zero, capped: false)
        let (front, _) = torus.split(planeNormal: axis, point: .zero)
        #expect(open.topology.boundaryLoopCount == 2)
        #expect(front.topology.boundaryLoopCount == 0)
        #expect(front.isManifold)
        #expect(front.topology.faces.contains { !$0.holeEdges.isEmpty } == expectHole)
    }

    @Test("Uncapped split leaves the cut open")
    func uncapped() {
        let sphere = Mesh.icoSphere(subdivisions: 2, attributes: [])
        let (front, back) = sphere.split(planeNormal: normal, point: point, capped: false)
        #expect(signedDistances(front).allSatisfy { $0 >= -1e-5 })
        #expect(signedDistances(back).allSatisfy { $0 <= 1e-5 })
        #expect(front.topology.boundaryLoopCount == 1)
        #expect(back.topology.boundaryLoopCount == 1)
        #expect(front.validate().isEmpty)
        #expect(back.validate().isEmpty)
    }

    @Test("Plane missing the mesh puts everything on one side")
    func planeOutside() {
        let box = Mesh.box(attributes: [])
        let (front, back) = box.split(planeNormal: [0, 0, 1], point: [0, 0, 5], capped: false)
        #expect(front.faceCount == 0)
        #expect(back.faceCount == TriangleSoup(mesh: box).triangleCount)
    }
}
