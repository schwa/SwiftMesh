import simd
import Testing
@testable import SwiftMesh

@Suite("PolygonMesh")
struct PolygonMeshTests {

    // MARK: - Construction

    @Test("Init from vertices and index arrays")
    func initIndexed() {
        let mesh = PolygonMesh(
            vertices: [
                SIMD3<Float>(0, 0, 0),
                SIMD3<Float>(1, 0, 0),
                SIMD3<Float>(1, 1, 0),
                SIMD3<Float>(0, 1, 0)
            ],
            faces: [[0, 1, 2, 3]]
        )
        #expect(mesh.vertices.count == 4)
        #expect(mesh.faces.count == 1)
        #expect(mesh.faces[0].vertices.count == 4)
        #expect(mesh.validate() == nil)
    }

    @Test("Init from vertices and Face structs")
    func initFaceStructs() {
        let face = PolygonMesh.Face(vertices: [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0.5, 1, 0)
        ])
        let mesh = PolygonMesh(
            vertices: [
                SIMD3<Float>(0, 0, 0),
                SIMD3<Float>(1, 0, 0),
                SIMD3<Float>(0.5, 1, 0)
            ],
            faces: [face]
        )
        #expect(mesh.vertices.count == 3)
        #expect(mesh.faces.count == 1)
        #expect(mesh.validate() == nil)
    }

    // MARK: - Edges

    @Test("Edges of a single quad")
    func quadEdges() {
        let mesh = PolygonMesh(
            vertices: [
                SIMD3<Float>(0, 0, 0),
                SIMD3<Float>(1, 0, 0),
                SIMD3<Float>(1, 1, 0),
                SIMD3<Float>(0, 1, 0)
            ],
            faces: [[0, 1, 2, 3]]
        )
        #expect(mesh.edges.count == 4)
    }

    @Test("Shared edges are not duplicated")
    func sharedEdges() {
        // Two triangles sharing edge 0→2
        let mesh = PolygonMesh(
            vertices: [
                SIMD3<Float>(0, 0, 0),
                SIMD3<Float>(1, 0, 0),
                SIMD3<Float>(1, 1, 0),
                SIMD3<Float>(0, 1, 0)
            ],
            faces: [[0, 1, 2], [0, 2, 3]]
        )
        // 3 + 3 = 6 half-edges, but 5 unique undirected edges (shared diagonal)
        #expect(mesh.edgeCount == 5)
    }

    // MARK: - Center

    @Test("Center of symmetric mesh")
    func center() {
        let mesh = PolygonMesh(
            vertices: [
                SIMD3<Float>(-1, -1, 0),
                SIMD3<Float>(1, -1, 0),
                SIMD3<Float>(1, 1, 0),
                SIMD3<Float>(-1, 1, 0)
            ],
            faces: [[0, 1, 2, 3]]
        )
        let c = mesh.center
        #expect(abs(c.x) < 1e-6)
        #expect(abs(c.y) < 1e-6)
        #expect(abs(c.z) < 1e-6)
    }

    // MARK: - Face properties

    @Test("Face normal")
    func faceNormal() {
        let face = PolygonMesh.Face(vertices: [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, 1, 0)
        ])
        let n = face.normal
        #expect(abs(n.x) < 1e-6)
        #expect(abs(n.y) < 1e-6)
        #expect(abs(n.z - 1.0) < 1e-6)
    }

    @Test("Face center")
    func faceCenter() {
        let face = PolygonMesh.Face(vertices: [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(3, 0, 0),
            SIMD3<Float>(0, 3, 0)
        ])
        let c = face.center
        #expect(abs(c.x - 1.0) < 1e-6)
        #expect(abs(c.y - 1.0) < 1e-6)
    }

    @Test("Face edges")
    func faceEdges() {
        let face = PolygonMesh.Face(vertices: [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(1, 1, 0)
        ])
        #expect(face.edges.count == 3)
    }

    @Test("Edge center")
    func edgeCenter() {
        let edge = PolygonMesh.Edge(
            start: SIMD3<Float>(0, 0, 0),
            end: SIMD3<Float>(2, 4, 6)
        )
        let c = edge.center
        #expect(abs(c.x - 1.0) < 1e-6)
        #expect(abs(c.y - 2.0) < 1e-6)
        #expect(abs(c.z - 3.0) < 1e-6)
    }

    // MARK: - Platonic Solids

    @Test("Tetrahedron")
    func tetrahedron() {
        let mesh = PolygonMesh.tetrahedron
        #expect(mesh.vertices.count == 4)
        #expect(mesh.faceCount == 4)
        #expect(mesh.edgeCount == 6)
        #expect(mesh.validate() == nil)
    }

    @Test("Cube")
    func cube() {
        let mesh = PolygonMesh.cube
        #expect(mesh.vertices.count == 8)
        #expect(mesh.faceCount == 6)
        #expect(mesh.edgeCount == 12)
        #expect(mesh.validate() == nil)
    }

    @Test("Octahedron")
    func octahedron() {
        let mesh = PolygonMesh.octahedron
        #expect(mesh.vertices.count == 6)
        #expect(mesh.faceCount == 8)
        #expect(mesh.edgeCount == 12)
        #expect(mesh.validate() == nil)
    }

    @Test("Dodecahedron")
    func dodecahedron() {
        let mesh = PolygonMesh.dodecahedron
        #expect(mesh.vertices.count == 20)
        #expect(mesh.faceCount == 12)
        #expect(mesh.edgeCount == 30)
        #expect(mesh.validate() == nil)
    }

    @Test("Icosahedron")
    func icosahedron() {
        let mesh = PolygonMesh.icosahedron
        #expect(mesh.vertices.count == 12)
        #expect(mesh.faceCount == 20)
        #expect(mesh.edgeCount == 30)
        #expect(mesh.validate() == nil)
    }

    // MARK: - Euler formula: V - E + F = 2 for closed polyhedra

    @Test("Euler formula for all Platonic solids")
    func eulerFormula() {
        let solids: [PolygonMesh] = [
            .tetrahedron, .cube, .octahedron, .dodecahedron, .icosahedron
        ]
        for solid in solids {
            let euler = solid.vertices.count - solid.edgeCount + solid.faceCount
            #expect(euler == 2)
        }
    }
}
