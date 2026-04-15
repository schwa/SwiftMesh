import simd
import Testing
@testable import SwiftMesh

@Suite("Mesh")
struct MeshTests {

    // MARK: - Construction

    @Test("Init from positions and face index arrays")
    func initIndexed() {
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0)
        ], faces: [[0, 1, 2, 3]])
        #expect(mesh.vertexCount == 4)
        #expect(mesh.faceCount == 1)
        #expect(mesh.validate() == nil)
    }

    @Test("Init from topology + positions")
    func initTopology() {
        let topo = HalfEdgeTopology(vertexCount: 3, faces: [.init(outer: [0, 1, 2])])
        let mesh = Mesh(topology: topo, positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0)
        ])
        #expect(mesh.vertexCount == 3)
        #expect(mesh.faceCount == 1)
        #expect(mesh.validate() == nil)
    }

    // MARK: - Accessors

    @Test("position(of:)")
    func positionAccessor() {
        let mesh = Mesh(positions: [
            SIMD3(3, 7, 1), SIMD3(5, 11, 2), SIMD3(9, 2, 3)
        ], faces: [[0, 1, 2]])
        let vid = HalfEdgeTopology.VertexID(raw: 1)
        let pos = mesh.position(of: vid)
        #expect(pos.x == 5)
        #expect(pos.y == 11)
        #expect(pos.z == 2)
    }

    @Test("facePositions returns correct points")
    func facePositions() {
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0)
        ], faces: [[0, 1, 2, 3]])
        let pts = mesh.facePositions(mesh.topology.faces[0].id)
        #expect(pts.count == 4)
    }

    @Test("center of symmetric mesh")
    func center() {
        let mesh = Mesh(positions: [
            SIMD3(-1, -1, 0), SIMD3(1, -1, 0), SIMD3(1, 1, 0), SIMD3(-1, 1, 0)
        ], faces: [[0, 1, 2, 3]])
        let c = mesh.center
        #expect(abs(c.x) < 1e-6)
        #expect(abs(c.y) < 1e-6)
        #expect(abs(c.z) < 1e-6)
    }

    @Test("edgeCount")
    func edgeCount() {
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0)
        ], faces: [[0, 1, 2], [0, 2, 3]])
        #expect(mesh.edgeCount == 5)
    }

    // MARK: - Face normals

    @Test("faceNormal for XY plane triangle")
    func faceNormalXY() {
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)
        ], faces: [[0, 1, 2]])
        let normal = mesh.faceNormal(mesh.topology.faces[0].id)
        #expect(abs(normal.x) < 1e-5)
        #expect(abs(normal.y) < 1e-5)
        #expect(abs(normal.z - 1.0) < 1e-5 || abs(normal.z + 1.0) < 1e-5)
    }

    @Test("faceCentroid")
    func faceCentroid() {
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(3, 0, 0), SIMD3(0, 3, 0)
        ], faces: [[0, 1, 2]])
        let c = mesh.faceCentroid(mesh.topology.faces[0].id)
        #expect(abs(c.x - 1.0) < 1e-6)
        #expect(abs(c.y - 1.0) < 1e-6)
        #expect(abs(c.z) < 1e-6)
    }

    // MARK: - Materials

    @Test("Default submesh contains all faces")
    func defaultSubmesh() {
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0)
        ], faces: [[0, 1, 2]])
        #expect(mesh.submeshes.count == 1)
        #expect(mesh.submeshes[0].faces.count == 1)
    }

    @Test("Explicit submeshes")
    func explicitSubmeshes() {
        let topo = HalfEdgeTopology(vertexCount: 4, faces: [
            .init(outer: [0, 1, 2]),
            .init(outer: [0, 2, 3])
        ])
        let mesh = Mesh(
            topology: topo,
            positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0)],
            submeshes: [
                .init(label: "A", faces: [topo.faces[0].id]),
                .init(label: "B", faces: [topo.faces[1].id])
            ]
        )
        #expect(mesh.submeshes.count == 2)
        #expect(mesh.submeshes[0].faces.count == 1)
        #expect(mesh.submeshes[1].faces.count == 1)
    }

    // MARK: - Validation

    @Test("Validate catches mismatched positions count")
    func validatePositionsMismatch() {
        let topo = HalfEdgeTopology(vertexCount: 3, faces: [.init(outer: [0, 1, 2])])
        let mesh = Mesh(topology: topo, positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0)])
        let error = mesh.validate()
        #expect(error != nil)
        #expect(error!.contains("positions.count"))
    }

    @Test("Validate catches mismatched normals count")
    func validateNormalsMismatch() {
        let topo = HalfEdgeTopology(vertexCount: 3, faces: [.init(outer: [0, 1, 2])])
        let mesh = Mesh(
            topology: topo,
            positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0)],
            normals: [SIMD3(0, 0, 1)] // wrong count
        )
        let error = mesh.validate()
        #expect(error != nil)
        #expect(error!.contains("normals.count"))
    }



    // MARK: - Platonic Solids

    @Test("Tetrahedron")
    func tetrahedron() {
        let mesh = Mesh.tetrahedron
        #expect(mesh.vertexCount == 4)
        #expect(mesh.faceCount == 4)
        #expect(mesh.edgeCount == 6)
        #expect(mesh.validate() == nil)
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("Cube")
    func cube() {
        let mesh = Mesh.cube
        #expect(mesh.vertexCount == 8)
        #expect(mesh.faceCount == 6)
        #expect(mesh.edgeCount == 12)
        #expect(mesh.validate() == nil)
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("Octahedron")
    func octahedron() {
        let mesh = Mesh.octahedron
        #expect(mesh.vertexCount == 6)
        #expect(mesh.faceCount == 8)
        #expect(mesh.edgeCount == 12)
        #expect(mesh.validate() == nil)
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("Icosahedron")
    func icosahedron() {
        let mesh = Mesh.icosahedron
        #expect(mesh.vertexCount == 12)
        #expect(mesh.faceCount == 20)
        #expect(mesh.edgeCount == 30)
        #expect(mesh.validate() == nil)
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("Dodecahedron")
    func dodecahedron() {
        let mesh = Mesh.dodecahedron
        #expect(mesh.vertexCount == 20)
        #expect(mesh.faceCount == 12)
        #expect(mesh.edgeCount == 30)
        #expect(mesh.validate() == nil)
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("Euler formula for all Platonic solids")
    func eulerFormula() {
        for solid in [Mesh.tetrahedron, .cube, .octahedron, .icosahedron, .dodecahedron] {
            #expect(solid.vertexCount - solid.edgeCount + solid.faceCount == 2)
        }
    }
}
