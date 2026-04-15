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
