import simd
@testable import SwiftMesh
import Testing

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
        let mesh = Mesh.tetrahedron(attributes: [])
        #expect(mesh.vertexCount == 4)
        #expect(mesh.faceCount == 4)
        #expect(mesh.edgeCount == 6)
        #expect(mesh.validate() == nil)
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("Cube")
    func cube() {
        let mesh = Mesh.cube(attributes: [])
        #expect(mesh.vertexCount == 8)
        #expect(mesh.faceCount == 6)
        #expect(mesh.edgeCount == 12)
        #expect(mesh.validate() == nil)
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("Octahedron")
    func octahedron() {
        let mesh = Mesh.octahedron(attributes: [])
        #expect(mesh.vertexCount == 6)
        #expect(mesh.faceCount == 8)
        #expect(mesh.edgeCount == 12)
        #expect(mesh.validate() == nil)
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("Icosahedron")
    func icosahedron() {
        let mesh = Mesh.icosahedron(attributes: [])
        #expect(mesh.vertexCount == 12)
        #expect(mesh.faceCount == 20)
        #expect(mesh.edgeCount == 30)
        #expect(mesh.validate() == nil)
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("Dodecahedron")
    func dodecahedron() {
        let mesh = Mesh.dodecahedron(attributes: [])
        #expect(mesh.vertexCount == 20)
        #expect(mesh.faceCount == 12)
        #expect(mesh.edgeCount == 30)
        #expect(mesh.validate() == nil)
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("Euler formula for all Platonic solids")
    func eulerFormula() {
        for solid in [Mesh.tetrahedron(attributes: []), .cube(attributes: []), .octahedron(attributes: []), .icosahedron(attributes: []), .dodecahedron(attributes: [])] {
            #expect(solid.vertexCount - solid.edgeCount + solid.faceCount == 2)
        }
    }

    // MARK: - Transforms

    @Test("translated(by:) offsets all positions")
    func translated() {
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)
        ], faces: [[0, 1, 2]])
        let moved = mesh.translated(by: [3, 4, 5])
        #expect(abs(moved.positions[0].x - 3) < 1e-6)
        #expect(abs(moved.positions[0].y - 4) < 1e-6)
        #expect(abs(moved.positions[0].z - 5) < 1e-6)
        #expect(abs(moved.positions[1].x - 4) < 1e-6)
        // Original unchanged
        #expect(mesh.positions[0].x == 0)
    }

    @Test("scaled(by:) uniform")
    func scaledUniform() {
        let mesh = Mesh(positions: [
            SIMD3(1, 2, 3), SIMD3(-1, -2, -3), SIMD3(0, 0, 0)
        ], faces: [[0, 1, 2]])
        let scaled = mesh.scaled(by: Float(2))
        #expect(abs(scaled.positions[0].x - 2) < 1e-6)
        #expect(abs(scaled.positions[0].y - 4) < 1e-6)
        #expect(abs(scaled.positions[0].z - 6) < 1e-6)
        #expect(abs(scaled.positions[1].x + 2) < 1e-6)
    }

    @Test("scaled(by:) per-axis")
    func scaledPerAxis() {
        let mesh = Mesh(positions: [
            SIMD3(1, 1, 1), SIMD3(0, 0, 0), SIMD3(2, 2, 2)
        ], faces: [[0, 1, 2]])
        let scaled = mesh.scaled(by: SIMD3<Float>(2, 3, 4))
        #expect(abs(scaled.positions[0].x - 2) < 1e-6)
        #expect(abs(scaled.positions[0].y - 3) < 1e-6)
        #expect(abs(scaled.positions[0].z - 4) < 1e-6)
    }

    @Test("scaled(by:) transforms normals by inverse-transpose")
    func scaledNormals() {
        let topo = HalfEdgeTopology(vertexCount: 3, faces: [.init(outer: [0, 1, 2])])
        let halfEdgeCount = topo.halfEdges.count
        let normals = Array(repeating: SIMD3<Float>(0, 0, 1), count: halfEdgeCount)
        let mesh = Mesh(
            topology: topo,
            positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)],
            normals: normals
        )
        // Non-uniform scale: stretch X by 2, Z normal should still point in Z
        let scaled = mesh.scaled(by: SIMD3<Float>(2, 1, 1))
        for n in scaled.normals! {
            #expect(abs(simd_length(n) - 1) < 1e-5)
            // Normal was (0,0,1), inverse-transpose of diag(2,1,1) is diag(0.5,1,1)
            // so transformed normal is (0,0,1) normalized = (0,0,1)
            #expect(abs(n.z - 1) < 1e-5)
        }
    }

    @Test("rotated(by:) 90° around Z")
    func rotated() {
        let mesh = Mesh(positions: [
            SIMD3(1, 0, 0), SIMD3(0, 0, 0), SIMD3(0, 1, 0)
        ], faces: [[0, 1, 2]])
        let rotation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        let rotated = mesh.rotated(by: rotation)
        // (1,0,0) rotated 90° around Z → (0,1,0)
        #expect(abs(rotated.positions[0].x) < 1e-5)
        #expect(abs(rotated.positions[0].y - 1) < 1e-5)
        #expect(abs(rotated.positions[0].z) < 1e-5)
    }

    @Test("transformed(by:) identity is no-op")
    func transformedIdentity() {
        let mesh = Mesh(positions: [
            SIMD3(1, 2, 3), SIMD3(4, 5, 6), SIMD3(7, 8, 9)
        ], faces: [[0, 1, 2]])
        let result = mesh.transformed(by: matrix_identity_float4x4)
        for i in mesh.positions.indices {
            #expect(abs(result.positions[i].x - mesh.positions[i].x) < 1e-5)
            #expect(abs(result.positions[i].y - mesh.positions[i].y) < 1e-5)
            #expect(abs(result.positions[i].z - mesh.positions[i].z) < 1e-5)
        }
    }

    @Test("transformed(by:) translation matrix")
    func transformedTranslation() {
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)
        ], faces: [[0, 1, 2]])
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4<Float>(10, 20, 30, 1)
        let result = mesh.transformed(by: matrix)
        #expect(abs(result.positions[0].x - 10) < 1e-5)
        #expect(abs(result.positions[0].y - 20) < 1e-5)
        #expect(abs(result.positions[0].z - 30) < 1e-5)
    }

    @Test("translate is mutating")
    func translateMutating() {
        var mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)
        ], faces: [[0, 1, 2]])
        mesh.translate(by: [1, 1, 1])
        #expect(abs(mesh.positions[0].x - 1) < 1e-6)
        #expect(abs(mesh.positions[0].y - 1) < 1e-6)
        #expect(abs(mesh.positions[0].z - 1) < 1e-6)
    }

    @Test("Transforms preserve topology")
    func transformsPreserveTopology() {
        let mesh = Mesh.cube(attributes: [])
        let translated = mesh.translated(by: [5, 5, 5])
        let scaled = mesh.scaled(by: Float(3))
        let rotated = mesh.rotated(by: simd_quatf(angle: .pi / 4, axis: SIMD3(0, 1, 0)))
        for m in [translated, scaled, rotated] {
            #expect(m.vertexCount == mesh.vertexCount)
            #expect(m.faceCount == mesh.faceCount)
            #expect(m.edgeCount == mesh.edgeCount)
            #expect(m.validate() == nil)
        }
    }
}
