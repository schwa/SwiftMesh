import simd
@testable import SwiftMesh
import Testing

@Suite("Edge chamfer")
struct EdgeChamferTests {
    private func checkClosedOutward(_ mesh: Mesh) {
        #expect(mesh.validate().isEmpty)
        #expect(mesh.isManifold)
        #expect(!mesh.topology.hasInconsistentFaceWinding)
        let center = (mesh.bounds.min + mesh.bounds.max) / 2
        for face in mesh.topology.faces {
            #expect(simd_dot(mesh.faceNormal(face.id), mesh.faceCentroid(face.id) - center) > 0)
        }
    }

    @Test("Chamfering every cube edge: 6 faces + 12 strips + 8 corner triangles")
    func allEdges() throws {
        let cube = Mesh.box(attributes: [])
        let mesh = try #require(cube.chamfered(distance: 0.1))
        #expect(mesh.faceCount == 26)
        #expect(mesh.vertexCount == 24)
        checkClosedOutward(mesh)
        // Original faces shrink to squares 0.8 wide, still on the cube's planes.
        let top = mesh.topology.faces.first { mesh.faceNormal($0.id).y > 0.99 }!
        let xs = mesh.facePositions(top.id).map(\.x)
        #expect(abs((xs.max()! - xs.min()!) - 0.8) < 1e-5)
        #expect(mesh.facePositions(top.id).allSatisfy { abs($0.y - 0.5) < 1e-6 })
    }

    @Test("Chamfering one cube edge adds one strip and turns two faces into pentagons")
    func oneEdge() throws {
        let cube = Mesh.box(attributes: [])
        let edge = cube.topology.halfEdges.first { $0.twin != nil }!.id
        let mesh = try #require(cube.chamfered(distance: 0.1, edges: [edge]))
        #expect(mesh.faceCount == 7)
        checkClosedOutward(mesh)
        #expect(mesh.topology.faces.filter { mesh.topology.halfEdgeLoop(for: $0.id).count == 5 }.count == 2)
    }

    @Test("Chamfering a closed triangle mesh keeps it closed and consistently wound")
    func icosahedron() throws {
        let mesh = try #require(Mesh.icosahedron(attributes: []).chamfered(distance: 0.05))
        #expect(mesh.faceCount == 20 + 30 + 12)
        checkClosedOutward(mesh)
    }

    @Test("Fillet: segmented strips on every cube edge stay closed and outward", arguments: [2, 4])
    func filletAllEdges(segments: Int) throws {
        let mesh = try #require(Mesh.box(attributes: []).chamfered(distance: 0.1, segments: segments))
        #expect(mesh.faceCount == 6 + 12 * segments + 8)
        checkClosedOutward(mesh)
        // The round bulges past the flat chamfer: along the (1, 1, 0) diagonal of an edge,
        // the furthest vertex is beyond the flat strip's midpoint but inside the original corner.
        let flat = try #require(Mesh.box(attributes: []).chamfered(distance: 0.1))
        let diagonal = simd_normalize(SIMD3<Float>(1, 1, 0))
        let reach = { (mesh: Mesh) in mesh.positions.map { simd_dot($0, diagonal) }.max()! }
        #expect(reach(mesh) > reach(flat) + 1e-4)
        #expect(reach(mesh) < simd_dot(SIMD3<Float>(0.5, 0.5, 0), diagonal))
    }

    @Test("Fillet on one cube edge closes the curved gap at each end")
    func filletOneEdge() throws {
        let cube = Mesh.box(attributes: [])
        let edge = cube.topology.halfEdges.first { $0.twin != nil }!.id
        let mesh = try #require(cube.chamfered(distance: 0.15, segments: 4, edges: [edge]))
        checkClosedOutward(mesh)
        // 6 faces + 4 strip quads + one patch per end filling between the arc and the absorbing face.
        #expect(mesh.faceCount == 6 + 4 + 2)
    }

    @Test("Fillet on an icosahedron stays closed and consistent")
    func filletIcosahedron() throws {
        let mesh = try #require(Mesh.icosahedron(attributes: []).chamfered(distance: 0.05, segments: 3))
        #expect(mesh.faceCount == 20 + 30 * 3 + 12)
        checkClosedOutward(mesh)
    }

    @Test("Open meshes are refused")
    func openMesh() {
        #expect(Mesh.quad(attributes: []).chamfered(distance: 0.1) == nil)
    }
}
