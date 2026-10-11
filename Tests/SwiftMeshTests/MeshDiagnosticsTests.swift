import simd
@testable import SwiftMesh
import Testing

@Suite("Mesh diagnostics")
struct MeshDiagnosticsTests {
    @Test("Clean closed mesh reports no problems")
    func cleanMesh() {
        let mesh = Mesh.icoSphere(subdivisions: 1, attributes: [])
        let topology = mesh.topology
        #expect(!topology.hasOrphanedVertices)
        #expect(!topology.hasDanglingEdges)
        #expect(!topology.hasNonConsistentTwins)
        #expect(!topology.hasNonConsistentNextPrev)
        #expect(topology.boundaryLoopCount == 0)
        #expect(!topology.hasDuplicateFaces)
        #expect(!topology.hasDuplicateEdges)
        #expect(!mesh.hasZeroAreaFaces())
        #expect(!mesh.hasNonPlanarFaces())
        #expect(topology.valenceHistogram() == [5: 12, 6: 30])
        #expect(topology.hasHighValenceVertices(threshold: 5))
        #expect(!topology.hasHighValenceVertices(threshold: 6))
    }

    @Test("Open quad has one boundary loop and dangling edges")
    func openQuad() {
        let mesh = Mesh(positions: [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]], faces: [[0, 1, 2, 3]])
        #expect(mesh.topology.boundaryLoopCount == 1)
        #expect(!mesh.topology.hasDanglingEdges) // boundary edges have a face and no twin
        #expect(!mesh.hasNonPlanarFaces())
    }

    @Test("Orphaned vertex, zero-area, non-planar, and duplicate faces are detected")
    func problems() {
        let positions: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [2, 0, 0], [0, 1, 0], [1, 1, 1], [5, 5, 5]]
        let mesh = Mesh(positions: positions, faces: [[0, 1, 2], [0, 1, 4, 3], [0, 1, 3], [1, 0, 3]])
        #expect(mesh.topology.hasOrphanedVertices)
        #expect(mesh.hasZeroAreaFaces())
        #expect(mesh.hasNonPlanarFaces())
        #expect(mesh.topology.hasDuplicateFaces)
        #expect(mesh.topology.hasDuplicateEdges)
    }

    @Test("Broken twin and next/prev links are detected")
    func brokenLinks() {
        var topology = Mesh.icoSphere(subdivisions: 0, attributes: []).topology
        topology.halfEdges[0].twin = topology.halfEdges[1].id
        topology.halfEdges[2].prev = topology.halfEdges[2].id
        #expect(topology.hasNonConsistentTwins)
        #expect(topology.hasNonConsistentNextPrev)
    }
}
