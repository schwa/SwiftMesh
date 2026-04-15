import simd
@testable import SwiftMesh
import Testing

@Suite("Mesh Primitives")
struct MeshPrimitivesTests {
    // MARK: - Simple Primitives

    @Test("triangle()")
    func triangle() {
        let mesh = Mesh.triangle(attributes: [])
        #expect(mesh.vertexCount == 3)
        #expect(mesh.faceCount == 1)
        #expect(mesh.validate().isEmpty)
    }

    @Test("quad()")
    func quad() {
        let mesh = Mesh.quad(attributes: [])
        #expect(mesh.vertexCount == 4)
        #expect(mesh.faceCount == 1)
        #expect(mesh.validate().isEmpty)
    }

    @Test("box()")
    func box() {
        let mesh = Mesh.box(attributes: [])
        #expect(mesh.vertexCount == 8)
        #expect(mesh.faceCount == 6)
        #expect(mesh.edgeCount == 12)
        #expect(mesh.validate().isEmpty)
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("cube(attributes: []) has no UVs or normals")
    func cubeNoAttributes() {
        let mesh = Mesh.cube(attributes: [])
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

    @Test("sphere(attributes: []) has no UVs or normals")
    func sphereNoAttributes() {
        let mesh = Mesh.sphere(attributes: [])
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
        #expect(mesh.validate().isEmpty)
    }

    @Test("cylinder(attributes: .textureCoordinates) has UVs")
    func cylinderUVs() {
        let mesh = Mesh.cylinder(segments: 8, attributes: .textureCoordinates)
        #expect(mesh.textureCoordinates != nil)
        #expect(mesh.textureCoordinates?.count == mesh.topology.halfEdges.count)
        #expect(mesh.validate().isEmpty)
    }

    @Test("cone(attributes: .textureCoordinates) has UVs")
    func coneUVs() {
        let mesh = Mesh.cone(segments: 8, attributes: .textureCoordinates)
        #expect(mesh.textureCoordinates != nil)
        #expect(mesh.textureCoordinates?.count == mesh.topology.halfEdges.count)
        #expect(mesh.validate().isEmpty)
    }

    @Test("tetrahedron(attributes: .textureCoordinates) has UVs")
    func tetrahedronUVs() {
        let mesh = Mesh.tetrahedron(attributes: .textureCoordinates)
        #expect(mesh.textureCoordinates != nil)
        #expect(mesh.textureCoordinates?.count == mesh.topology.halfEdges.count)
        #expect(mesh.validate().isEmpty)
    }

    @Test("octahedron(attributes: .textureCoordinates) has UVs")
    func octahedronUVs() {
        let mesh = Mesh.octahedron(attributes: .textureCoordinates)
        #expect(mesh.textureCoordinates != nil)
        #expect(mesh.textureCoordinates?.count == mesh.topology.halfEdges.count)
        #expect(mesh.validate().isEmpty)
    }

    @Test("icosahedron(attributes: .textureCoordinates) has UVs")
    func icosahedronUVs() {
        let mesh = Mesh.icosahedron(attributes: .textureCoordinates)
        #expect(mesh.textureCoordinates != nil)
        #expect(mesh.textureCoordinates?.count == mesh.topology.halfEdges.count)
        #expect(mesh.validate().isEmpty)
    }

    @Test("dodecahedron(attributes: .textureCoordinates) has UVs")
    func dodecahedronUVs() {
        let mesh = Mesh.dodecahedron(attributes: .textureCoordinates)
        #expect(mesh.textureCoordinates != nil)
        #expect(mesh.textureCoordinates?.count == mesh.topology.halfEdges.count)
        #expect(mesh.validate().isEmpty)
    }

    @Test("torus(attributes: .textureCoordinates) has UVs")
    func torusUVs() {
        let mesh = Mesh.torus(majorSegments: 8, minorSegments: 4, attributes: .textureCoordinates)
        #expect(mesh.textureCoordinates != nil)
        #expect(mesh.textureCoordinates?.count == mesh.topology.halfEdges.count)
        #expect(mesh.validate().isEmpty)
    }

    // MARK: - Parametric Surfaces

    @Test("sphere() default")
    func sphereDefault() {
        let mesh = Mesh.sphere(attributes: [])
        #expect(mesh.validate().isEmpty)
        #expect(mesh.vertexCount == 2 + (16 - 1) * 32) // poles + rings
        // Euler: V - E + F = 2
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("sphere() triangulates for MetalMesh")
    func sphereTriangulates() {
        let mesh = Mesh.sphere(latitudeSegments: 4, longitudeSegments: 8, attributes: [])
        let tris = mesh.triangulate()
        // Top cap: 8 triangles, bottom cap: 8 triangles, 2 quad rings × 8 = 16 quads → 32 triangles
        // Total: 8 + 32 + 8 = 48
        #expect(tris.count == 48)
    }

    @Test("torus() default")
    func torusDefault() {
        let mesh = Mesh.torus(attributes: [])
        #expect(mesh.validate().isEmpty)
        #expect(mesh.faceCount == 32 * 16)
        // Torus Euler: V - E + F = 0
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 0)
    }

    @Test("cylinder() capped")
    func cylinderCapped() {
        let mesh = Mesh.cylinder(segments: 8, capped: true, attributes: [])
        #expect(mesh.validate().isEmpty)
        // 8 side quads + 2 n-gon caps
        #expect(mesh.faceCount == 10)
        // Euler: V - E + F = 2
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("cylinder() uncapped")
    func cylinderUncapped() {
        let mesh = Mesh.cylinder(segments: 8, capped: false, attributes: [])
        #expect(mesh.validate().isEmpty)
        #expect(mesh.faceCount == 8)
    }

    @Test("cone() capped")
    func coneCapped() {
        let mesh = Mesh.cone(segments: 8, capped: true, attributes: [])
        #expect(mesh.validate().isEmpty)
        // 8 side triangles + 1 base cap
        #expect(mesh.faceCount == 9)
        // Euler: V - E + F = 2
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("cone() uncapped")
    func coneUncapped() {
        let mesh = Mesh.cone(segments: 8, capped: false, attributes: [])
        #expect(mesh.validate().isEmpty)
        #expect(mesh.faceCount == 8)
    }

    // MARK: - Rectangular Frustum

    @Test("rectangularFrustum() capped")
    func rectangularFrustumCapped() {
        let mesh = Mesh.rectangularFrustum(capped: true, attributes: [])
        #expect(mesh.validate().isEmpty)
        // 4 side quads + 2 caps
        #expect(mesh.faceCount == 6)
        #expect(mesh.vertexCount == 8)
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("rectangularFrustum() uncapped")
    func rectangularFrustumUncapped() {
        let mesh = Mesh.rectangularFrustum(capped: false, attributes: [])
        #expect(mesh.validate().isEmpty)
        #expect(mesh.faceCount == 4)
    }

    @Test("rectangularFrustum(attributes: .textureCoordinates) has UVs")
    func rectangularFrustumUVs() {
        let mesh = Mesh.rectangularFrustum(attributes: .textureCoordinates)
        #expect(mesh.textureCoordinates != nil)
        #expect(mesh.textureCoordinates?.count == mesh.topology.halfEdges.count)
        #expect(mesh.validate().isEmpty)
    }

    // MARK: - Conical Frustum

    @Test("conicalFrustum() capped")
    func conicalFrustumCapped() {
        let mesh = Mesh.conicalFrustum(segments: 8, capped: true, attributes: [])
        #expect(mesh.validate().isEmpty)
        // 8 side quads + 2 caps
        #expect(mesh.faceCount == 10)
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("conicalFrustum() uncapped")
    func conicalFrustumUncapped() {
        let mesh = Mesh.conicalFrustum(segments: 8, capped: false, attributes: [])
        #expect(mesh.validate().isEmpty)
        #expect(mesh.faceCount == 8)
    }

    @Test("conicalFrustum(attributes: .textureCoordinates) has UVs")
    func conicalFrustumUVs() {
        let mesh = Mesh.conicalFrustum(segments: 8, attributes: .textureCoordinates)
        #expect(mesh.textureCoordinates != nil)
        #expect(mesh.textureCoordinates?.count == mesh.topology.halfEdges.count)
        #expect(mesh.validate().isEmpty)
    }

    // MARK: - Circle

    @Test("circle()")
    func circle() {
        let mesh = Mesh.circle(segments: 8, attributes: [])
        #expect(mesh.validate().isEmpty)
        #expect(mesh.vertexCount == 9) // center + 8 rim
        #expect(mesh.faceCount == 8)
    }

    @Test("circle(attributes: .textureCoordinates) has UVs")
    func circleUVs() {
        let mesh = Mesh.circle(segments: 8, attributes: .textureCoordinates)
        #expect(mesh.textureCoordinates != nil)
        #expect(mesh.textureCoordinates?.count == mesh.topology.halfEdges.count)
        #expect(mesh.validate().isEmpty)
    }

    // MARK: - IcoSphere & CubeSphere

    @Test("icoSphere() subdivisions=0 is icosahedron")
    func icoSphereZero() {
        let mesh = Mesh.icoSphere(subdivisions: 0, attributes: [])
        #expect(mesh.validate().isEmpty)
        #expect(mesh.vertexCount == 12)
        #expect(mesh.faceCount == 20)
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("icoSphere() subdivisions=1")
    func icoSphereOne() {
        let mesh = Mesh.icoSphere(subdivisions: 1, attributes: [])
        #expect(mesh.validate().isEmpty)
        #expect(mesh.faceCount == 80) // 20 × 4
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("icoSphere(attributes: .textureCoordinates) has UVs")
    func icoSphereUVs() {
        let mesh = Mesh.icoSphere(subdivisions: 1, attributes: .textureCoordinates)
        #expect(mesh.textureCoordinates != nil)
        #expect(mesh.textureCoordinates?.count == mesh.topology.halfEdges.count)
        #expect(mesh.validate().isEmpty)
    }

    @Test("cubeSphere()")
    func cubeSphere() {
        let mesh = Mesh.cubeSphere(subdivisions: 2, attributes: [])
        #expect(mesh.validate().isEmpty)
        #expect(mesh.faceCount == 6 * 4) // 6 faces × 2×2 quads
        // After welding: 8 corners + 12 edge midpoints + 6 face centers = 26
        #expect(mesh.vertexCount == 26)
        #expect(mesh.isManifold)
    }

    @Test("cubeSphere(attributes: .textureCoordinates) has UVs")
    func cubeSphereUVs() {
        let mesh = Mesh.cubeSphere(subdivisions: 2, attributes: .textureCoordinates)
        #expect(mesh.textureCoordinates != nil)
        #expect(mesh.textureCoordinates?.count == mesh.topology.halfEdges.count)
        #expect(mesh.validate().isEmpty)
    }

    // MARK: - Hemisphere & Capsule

    @Test("hemisphere() capped")
    func hemisphereCapped() {
        let mesh = Mesh.hemisphere(segments: 8, latitudeSegments: 4, capped: true, attributes: [])
        #expect(mesh.validate().isEmpty)
        // pole cap: 8 tri + 3 quad strips × 8 + 1 base cap = 8 + 24 + 1 = 33
        #expect(mesh.faceCount == 33)
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("hemisphere() uncapped")
    func hemisphereUncapped() {
        let mesh = Mesh.hemisphere(segments: 8, latitudeSegments: 4, capped: false, attributes: [])
        #expect(mesh.validate().isEmpty)
        #expect(mesh.faceCount == 32) // 8 tri + 3 × 8 quads
    }

    @Test("hemisphere(attributes: .textureCoordinates) has UVs")
    func hemisphereUVs() {
        let mesh = Mesh.hemisphere(segments: 8, latitudeSegments: 4, attributes: .textureCoordinates)
        #expect(mesh.textureCoordinates != nil)
        #expect(mesh.textureCoordinates?.count == mesh.topology.halfEdges.count)
        #expect(mesh.validate().isEmpty)
    }

    @Test("capsule()")
    func capsule() {
        let mesh = Mesh.capsule(segments: 8, height: 1.0, radius: 0.25, latitudeSegments: 4, attributes: [])
        #expect(mesh.validate().isEmpty)
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("capsule() with zero cylinder height")
    func capsuleZeroCylinder() {
        // height <= 2*radius means no cylinder section, just a sphere
        let mesh = Mesh.capsule(segments: 8, height: 0.5, radius: 0.25, latitudeSegments: 4, attributes: [])
        #expect(mesh.validate().isEmpty)
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("capsule(attributes: .textureCoordinates) has UVs")
    func capsuleUVs() {
        let mesh = Mesh.capsule(segments: 8, height: 1.0, radius: 0.25, latitudeSegments: 4, attributes: .textureCoordinates)
        #expect(mesh.textureCoordinates != nil)
        #expect(mesh.textureCoordinates?.count == mesh.topology.halfEdges.count)
        #expect(mesh.validate().isEmpty)
    }

    // MARK: - Bundled Meshes

    @Test("teapot()")
    func teapot() {
        let mesh = Mesh.teapot(attributes: [])
        #expect(mesh.vertexCount > 0)
        #expect(mesh.faceCount > 0)
    }

    // MARK: - Platonic Solids Euler formula

    @Test("All Platonic solids satisfy Euler formula")
    func eulerFormula() {
        let solids: [(String, Mesh)] = [
            ("tetrahedron", .tetrahedron(attributes: [])),
            ("cube", .cube(attributes: [])),
            ("octahedron", .octahedron(attributes: [])),
            ("icosahedron", .icosahedron(attributes: [])),
            ("dodecahedron", .dodecahedron(attributes: []))
        ]
        for (name, mesh) in solids {
            let euler = mesh.vertexCount - mesh.edgeCount + mesh.faceCount
            #expect(euler == 2, "Euler formula failed for \(name): V=\(mesh.vertexCount) E=\(mesh.edgeCount) F=\(mesh.faceCount)")
            #expect(mesh.validate().isEmpty, "\(name) failed validation")
        }
    }
}
