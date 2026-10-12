import simd
@testable import SwiftMesh
import Testing

@Suite("Boolean degenerate removal")
struct DegenerateRemovalTests {
    private func volume(_ mesh: BooleanMesh) -> Double {
        (0..<mesh.numTri).reduce(0) { total, tri in
            let v = (0..<3).map { mesh.vertPos[mesh.halfedges[3 * tri + $0].startVert] }
            return total + simd_dot(v[0], simd_cross(v[1], v[2])) / 6
        }
    }

    private func shortestEdge(_ mesh: BooleanMesh) -> Double {
        mesh.halfedges.map { simd_length(mesh.vertPos[$0.endVert] - mesh.vertPos[$0.startVert]) }.min() ?? .infinity
    }

    private func boolean(_ a: Mesh, _ b: Mesh, _ operation: BooleanOperation) throws -> BooleanMesh {
        BooleanAssembler(try BooleanMesh(mesh: a), try BooleanMesh(mesh: b), operation: operation).assemble().triangulated()
    }

    private func checkClean(_ before: BooleanMesh, _ after: BooleanMesh, _ label: String) {
        #expect(after.isManifold, "\(label)")
        #expect(after.degenerateTriangleCount == 0, "\(label)")
        #expect(shortestEdge(after) > after.epsilon, "\(label)")
        #expect(abs(volume(after) - volume(before)) < 1e-9, "\(label)")
        #expect(after.vertPos.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }, "\(label)")
    }

    @Test("Coplanar cube booleans: degenerates removed, volume kept", arguments: [BooleanOperation.union, .intersection, .difference])
    func cubes(operation: BooleanOperation) throws {
        let before = try boolean(.cube(attributes: []), Mesh.cube(attributes: []).translated(by: [0.5, 0.25, 0]), operation)
        let after = before.removingDegenerates()
        checkClean(before, after, "\(operation)")
        #expect(after.numTri <= before.numTri)
    }

    @Test("Random rotations: every cleaned result stays manifold with no degenerates")
    func randomRotations() throws {
        var state: UInt64 = 23
        func next() -> Float {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(state >> 40) / Float(1 << 24)
        }
        let sphere = Mesh.icoSphere(extents: [0.9, 0.9, 0.9], subdivisions: 2, attributes: [])
        for _ in 0..<20 {
            let axis = simd_normalize(SIMD3(next() - 0.5, next() - 0.5, next() - 0.5) + [0.01, 0, 0])
            let rotation = simd_float4x4(simd_quatf(angle: next() * 6.28, axis: axis))
            let offset = SIMD3(next() - 0.5, next() - 0.5, next() - 0.5) * 0.6
            let cube = Mesh.cube(extents: [0.6, 0.6, 0.6], attributes: []).transformed(by: rotation).translated(by: offset)
            for operation in [BooleanOperation.union, .intersection, .difference] {
                let before = try boolean(sphere, cube, operation)
                checkClean(before, before.removingDegenerates(), "\(operation) \(offset)")
            }
        }
    }

    @Test("A vertex inserted on a cube edge is collapsed back")
    func colinearVertex() throws {
        var cube = Mesh.cube(attributes: []).triangulated()
        cube.splitEdge(cube.topology.halfEdges.first { $0.twin != nil }!.id)
        let before = try BooleanMesh(mesh: cube)
        #expect(before.numVert == 9)
        let after = before.removingDegenerates()
        #expect(after.numVert == 8)
        #expect(after.numTri == 12)
        checkClean(before, after, "split cube")
    }

    @Test("Clean meshes are unchanged")
    func clean() throws {
        let sphere = try BooleanMesh(mesh: .icoSphere(subdivisions: 2, attributes: []))
        let after = sphere.removingDegenerates()
        #expect(after.numTri == sphere.numTri)
        #expect(after.numVert == sphere.numVert)
    }
}
