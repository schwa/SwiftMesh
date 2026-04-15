import simd
@testable import SwiftMesh
import Testing

@Suite("Triangulation")
struct TriangulationTests {
    @Test("Triangle face produces one triangle")
    func triangleFace() {
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0)
        ], faces: [[0, 1, 2]])
        let tris = mesh.triangulate()
        #expect(tris.count == 1)
        let rawIDs = Set([tris[0].0.raw, tris[0].1.raw, tris[0].2.raw])
        #expect(rawIDs == [0, 1, 2])
    }

    @Test("Quad face produces two triangles")
    func quadFace() {
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0)
        ], faces: [[0, 1, 2, 3]])
        let tris = mesh.triangulate()
        #expect(tris.count == 2)
        // All vertex IDs should come from the original 4
        for tri in tris {
            #expect((0...3).contains(tri.0.raw))
            #expect((0...3).contains(tri.1.raw))
            #expect((0...3).contains(tri.2.raw))
        }
    }

    @Test("Pentagon produces three triangles")
    func pentagonFace() {
        // Regular pentagon in XY plane
        let positions: [SIMD3<Float>] = (0..<5).map { idx in
            let angle = Float(idx) * (2 * .pi / 5)
            return SIMD3(cos(angle), sin(angle), 0)
        }
        let mesh = Mesh(positions: positions, faces: [[0, 1, 2, 3, 4]])
        let tris = mesh.triangulate()
        #expect(tris.count == 3) // n-2 triangles for convex n-gon
    }

    @Test("Cube faces (quads) all triangulate")
    func cubeTriangulation() {
        let tris = Mesh.cube(attributes: []).triangulate()
        // 6 quad faces × 2 triangles each = 12
        #expect(tris.count == 12)
    }

    @Test("Dodecahedron faces (pentagons) all triangulate")
    func dodecahedronTriangulation() {
        let tris = Mesh.dodecahedron(attributes: []).triangulate()
        // 12 pentagon faces × 3 triangles each = 36
        #expect(tris.count == 36)
    }

    @Test("Non-planar quad triangulates")
    func nonPlanarQuad() {
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0.5)
        ], faces: [[0, 1, 2, 3]])
        let tris = mesh.triangulate()
        #expect(tris.count == 2)
    }

    @Test("Multiple faces triangulate independently")
    func multipleFaces() {
        // One triangle + one quad
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0),
            SIMD3(2, 0, 0), SIMD3(3, 0, 0), SIMD3(3, 1, 0), SIMD3(2, 1, 0)
        ], faces: [[0, 1, 2], [3, 4, 5, 6]])
        let tris = mesh.triangulate()
        #expect(tris.count == 3) // 1 + 2
    }

    @Test("L-shaped concave polygon triangulates correctly")
    func concavePolygon() {
        // L-shape in XY plane (concave)
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(2, 0, 0), SIMD3(2, 1, 0),
            SIMD3(1, 1, 0), SIMD3(1, 2, 0), SIMD3(0, 2, 0)
        ], faces: [[0, 1, 2, 3, 4, 5]])
        let tris = mesh.triangulate()
        #expect(tris.count == 4) // 6 vertices → 4 triangles
    }

    // MARK: - triangulated() → Mesh

    @Test("triangulated() on all-triangle mesh is identity")
    func triangulatedIdentity() {
        let mesh = Mesh.icosahedron(attributes: [])
        let result = mesh.triangulated()
        #expect(result.faceCount == mesh.faceCount)
        #expect(result.vertexCount == mesh.vertexCount)
        #expect(result.validate().isEmpty)
    }

    @Test("triangulated() cube: 6 quads → 12 triangles")
    func triangulatedCube() {
        let mesh = Mesh.cube(attributes: [])
        let result = mesh.triangulated()
        #expect(result.faceCount == 12)
        #expect(result.vertexCount == mesh.vertexCount)
        #expect(result.validate().isEmpty)
        // Every face should be a triangle
        for face in result.topology.faces {
            let loop = result.topology.vertexLoop(for: face.id)
            #expect(loop.count == 3)
        }
    }

    @Test("triangulated() dodecahedron: 12 pentagons → 36 triangles")
    func triangulatedDodecahedron() {
        let mesh = Mesh.dodecahedron(attributes: [])
        let result = mesh.triangulated()
        #expect(result.faceCount == 36)
        for face in result.topology.faces {
            let loop = result.topology.vertexLoop(for: face.id)
            #expect(loop.count == 3)
        }
    }

    @Test("triangulated() preserves vertex positions")
    func triangulatedPreservesPositions() {
        let mesh = Mesh.cube(attributes: [])
        let result = mesh.triangulated()
        // Same positions array
        #expect(result.positions.count == mesh.positions.count)
        for i in mesh.positions.indices {
            #expect(result.positions[i] == mesh.positions[i])
        }
    }

    @Test("triangulated() validates")
    func triangulatedValidates() {
        let mesh = Mesh.dodecahedron(attributes: [])
        let result = mesh.triangulated()
        #expect(result.validate().isEmpty)
    }

    @Test("triangulated() mixed faces (triangle + quad)")
    func triangulatedMixed() {
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0),
            SIMD3(2, 0, 0), SIMD3(3, 0, 0), SIMD3(3, 1, 0), SIMD3(2, 1, 0)
        ], faces: [[0, 1, 2], [3, 4, 5, 6]])
        let result = mesh.triangulated()
        #expect(result.faceCount == 3) // 1 tri + 2 from quad
        for face in result.topology.faces {
            let loop = result.topology.vertexLoop(for: face.id)
            #expect(loop.count == 3)
        }
    }

    @Test("triangulated() on already-triangulated mesh doesn't change face count")
    func triangulatedNoOp() {
        let mesh = Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 2, attributes: [])
        let result = mesh.triangulated()
        #expect(result.faceCount == mesh.faceCount)
    }
}
