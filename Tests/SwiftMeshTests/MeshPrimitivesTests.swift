import simd
@testable import SwiftMesh
import Testing

@Suite("Mesh Primitives")
struct MeshPrimitivesTests {
    // MARK: - Simple Primitives

    @Test("triangle()")
    func triangle() {
        let mesh = Mesh.triangle()
        #expect(mesh.vertexCount == 3)
        #expect(mesh.faceCount == 1)
        #expect(mesh.validate() == nil)
    }

    @Test("quad()")
    func quad() {
        let mesh = Mesh.quad()
        #expect(mesh.vertexCount == 4)
        #expect(mesh.faceCount == 1)
        #expect(mesh.validate() == nil)
    }

    @Test("box()")
    func box() {
        let mesh = Mesh.box()
        #expect(mesh.vertexCount == 8)
        #expect(mesh.faceCount == 6)
        #expect(mesh.edgeCount == 12)
        #expect(mesh.validate() == nil)
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("cube() without attributes has no UVs")
    func cubeNoAttributes() {
        let mesh = Mesh.cube()
        #expect(mesh.textureCoordinates == nil)
        #expect(mesh.normals == nil)
    }

    @Test("cube(attributes: .textureCoordinates) has per-corner UVs")
    func cubeUVs() throws {
        let mesh = Mesh.cube(attributes: .textureCoordinates)
        let uvs = try #require(mesh.textureCoordinates)
        #expect(uvs.count == mesh.topology.halfEdges.count)
        // Each quad face should have corners mapped to [0,0], [1,0], [1,1], [0,1]
        for face in mesh.topology.faces {
            let heLoop = mesh.topology.halfEdgeLoop(for: face.id)
            #expect(heLoop.count == 4)
            let faceUVs = heLoop.map { uvs[$0.raw] }
            #expect(faceUVs[0] == SIMD2<Float>(0, 0))
            #expect(faceUVs[1] == SIMD2<Float>(1, 0))
            #expect(faceUVs[2] == SIMD2<Float>(1, 1))
            #expect(faceUVs[3] == SIMD2<Float>(0, 1))
        }
    }

    @Test("cube(attributes: .flatNormals) has flat normals")
    func cubeFlatNormals() {
        let mesh = Mesh.cube(attributes: .flatNormals)
        #expect(mesh.normals != nil)
        #expect(mesh.normals?.count == mesh.topology.halfEdges.count)
    }

    @Test("sphere(attributes: .textureCoordinates) has UVs")
    func sphereUVs() {
        let mesh = Mesh.sphere(attributes: .textureCoordinates)
        #expect(mesh.textureCoordinates != nil)
        #expect(mesh.textureCoordinates?.count == mesh.topology.halfEdges.count)
    }

    @Test("sphere() without attributes has no UVs")
    func sphereNoAttributes() {
        let mesh = Mesh.sphere()
        #expect(mesh.textureCoordinates == nil)
        #expect(mesh.normals == nil)
    }

    @Test("triangle(attributes: .textureCoordinates) has UVs")
    func triangleUVs() throws {
        let mesh = Mesh.triangle(attributes: .textureCoordinates)
        let uvs = try #require(mesh.textureCoordinates)
        #expect(uvs.count == mesh.topology.halfEdges.count)
    }

    @Test("quad(attributes: .textureCoordinates) has per-corner UVs")
    func quadUVs() throws {
        let mesh = Mesh.quad(attributes: .textureCoordinates)
        let uvs = try #require(mesh.textureCoordinates)
        #expect(uvs.count == mesh.topology.halfEdges.count)
        let heLoop = mesh.topology.halfEdgeLoop(for: HalfEdgeTopology.FaceID(raw: 0))
        #expect(uvs[heLoop[0].raw] == SIMD2<Float>(0, 0))
        #expect(uvs[heLoop[1].raw] == SIMD2<Float>(1, 0))
        #expect(uvs[heLoop[2].raw] == SIMD2<Float>(1, 1))
        #expect(uvs[heLoop[3].raw] == SIMD2<Float>(0, 1))
    }

    @Test("box(attributes: .textureCoordinates) has per-corner UVs")
    func boxUVs() {
        let mesh = Mesh.box(attributes: .textureCoordinates)
        #expect(mesh.textureCoordinates != nil)
        #expect(mesh.textureCoordinates?.count == mesh.topology.halfEdges.count)
        #expect(mesh.validate() == nil)
    }

    @Test("cylinder(attributes: .textureCoordinates) has UVs")
    func cylinderUVs() {
        let mesh = Mesh.cylinder(segments: 8, attributes: .textureCoordinates)
        #expect(mesh.textureCoordinates != nil)
        #expect(mesh.textureCoordinates?.count == mesh.topology.halfEdges.count)
        #expect(mesh.validate() == nil)
    }

    @Test("cone(attributes: .textureCoordinates) has UVs")
    func coneUVs() {
        let mesh = Mesh.cone(segments: 8, attributes: .textureCoordinates)
        #expect(mesh.textureCoordinates != nil)
        #expect(mesh.textureCoordinates?.count == mesh.topology.halfEdges.count)
        #expect(mesh.validate() == nil)
    }

    // MARK: - Parametric Surfaces

    @Test("sphere() default")
    func sphereDefault() {
        let mesh = Mesh.sphere()
        #expect(mesh.validate() == nil)
        #expect(mesh.vertexCount == 2 + (16 - 1) * 32) // poles + rings
        // Euler: V - E + F = 2
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("sphere() triangulates for MetalMesh")
    func sphereTriangulates() {
        let mesh = Mesh.sphere(latitudeSegments: 4, longitudeSegments: 8)
        let tris = mesh.triangulate()
        // Top cap: 8 triangles, bottom cap: 8 triangles, 2 quad rings × 8 = 16 quads → 32 triangles
        // Total: 8 + 32 + 8 = 48
        #expect(tris.count == 48)
    }

    @Test("torus() default")
    func torusDefault() {
        let mesh = Mesh.torus()
        #expect(mesh.validate() == nil)
        #expect(mesh.faceCount == 32 * 16)
        // Torus Euler: V - E + F = 0
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 0)
    }

    @Test("cylinder() capped")
    func cylinderCapped() {
        let mesh = Mesh.cylinder(segments: 8, capped: true)
        #expect(mesh.validate() == nil)
        // 8 side quads + 2 n-gon caps
        #expect(mesh.faceCount == 10)
        // Euler: V - E + F = 2
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("cylinder() uncapped")
    func cylinderUncapped() {
        let mesh = Mesh.cylinder(segments: 8, capped: false)
        #expect(mesh.validate() == nil)
        #expect(mesh.faceCount == 8)
    }

    @Test("cone() capped")
    func coneCapped() {
        let mesh = Mesh.cone(segments: 8, capped: true)
        #expect(mesh.validate() == nil)
        // 8 side triangles + 1 base cap
        #expect(mesh.faceCount == 9)
        // Euler: V - E + F = 2
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("cone() uncapped")
    func coneUncapped() {
        let mesh = Mesh.cone(segments: 8, capped: false)
        #expect(mesh.validate() == nil)
        #expect(mesh.faceCount == 8)
    }

    // MARK: - Platonic Solids Euler formula

    @Test("All Platonic solids satisfy Euler formula")
    func eulerFormula() {
        let solids: [(String, Mesh)] = [
            ("tetrahedron", .tetrahedron()),
            ("cube", .cube()),
            ("octahedron", .octahedron()),
            ("icosahedron", .icosahedron()),
            ("dodecahedron", .dodecahedron())
        ]
        for (name, mesh) in solids {
            let euler = mesh.vertexCount - mesh.edgeCount + mesh.faceCount
            #expect(euler == 2, "Euler formula failed for \(name): V=\(mesh.vertexCount) E=\(mesh.edgeCount) F=\(mesh.faceCount)")
            #expect(mesh.validate() == nil, "\(name) failed validation")
        }
    }
}
