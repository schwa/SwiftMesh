import simd
@testable import SwiftMesh
import Testing

@Suite("Subdivision")
struct SubdivisionTests {
    // MARK: - Loop Subdivision

    @Test("Loop subdivision of tetrahedron produces valid mesh")
    func loopTetrahedron() {
        let mesh = Mesh.tetrahedron(attributes: [])
        let subdivided = mesh.loopSubdivided(iterations: 1)
        // 4 faces × 4 = 16 faces
        #expect(subdivided.faceCount == 16)
        #expect(subdivided.validate() == nil)
    }

    @Test("Loop subdivision preserves closed manifold (Euler)")
    func loopEuler() {
        let mesh = Mesh.tetrahedron(attributes: [])
        let subdivided = mesh.loopSubdivided(iterations: 1)
        // Closed manifold: V - E + F = 2
        #expect(subdivided.vertexCount - subdivided.edgeCount + subdivided.faceCount == 2)
    }

    @Test("Loop subdivision of icosahedron")
    func loopIcosahedron() {
        let mesh = Mesh.icosahedron(attributes: [])
        let subdivided = mesh.loopSubdivided(iterations: 1)
        // 20 faces × 4 = 80
        #expect(subdivided.faceCount == 80)
        // 12 original + 30 edge points = 42 vertices
        #expect(subdivided.vertexCount == 42)
        #expect(subdivided.validate() == nil)
        #expect(subdivided.vertexCount - subdivided.edgeCount + subdivided.faceCount == 2)
    }

    @Test("Loop subdivision two iterations")
    func loopTwoIterations() {
        let mesh = Mesh.octahedron(attributes: [])
        let sub1 = mesh.loopSubdivided(iterations: 1)
        let sub2 = mesh.loopSubdivided(iterations: 2)
        // Each iteration 4× the faces
        #expect(sub1.faceCount == 8 * 4)
        #expect(sub2.faceCount == 8 * 4 * 4)
        #expect(sub2.validate() == nil)
    }

    @Test("Loop subdivision smooths toward sphere")
    func loopSmoothing() {
        // An icosahedron with Loop subdivision should approach a sphere.
        // After a few iterations, all vertices should be near-equidistant from center.
        let mesh = Mesh.icosahedron(extents: [2, 2, 2], attributes: [])
        let subdivided = mesh.loopSubdivided(iterations: 3)

        let center = subdivided.center
        let distances = subdivided.positions.map { simd_distance($0, center) }
        let minDist = distances.min()!
        let maxDist = distances.max()!

        // Should be fairly spherical — within 10% variation
        let variation = (maxDist - minDist) / ((maxDist + minDist) / 2)
        #expect(variation < 0.1)
    }

    @Test("Loop subdivision zero iterations returns same mesh")
    func loopZeroIterations() {
        let mesh = Mesh.tetrahedron(attributes: [])
        let result = mesh.loopSubdivided(iterations: 0)
        #expect(result.faceCount == mesh.faceCount)
        #expect(result.vertexCount == mesh.vertexCount)
    }

    // MARK: - Catmull-Clark Subdivision

    @Test("Catmull-Clark subdivision of cube produces valid mesh")
    func catmullClarkCube() {
        let mesh = Mesh.cube(attributes: [])
        let subdivided = mesh.catmullClarkSubdivided(iterations: 1)
        // 6 quad faces × 4 corners = 24 new quads
        #expect(subdivided.faceCount == 24)
        #expect(subdivided.validate() == nil)
    }

    @Test("Catmull-Clark preserves closed manifold (Euler)")
    func catmullClarkEuler() {
        let mesh = Mesh.cube(attributes: [])
        let subdivided = mesh.catmullClarkSubdivided(iterations: 1)
        #expect(subdivided.vertexCount - subdivided.edgeCount + subdivided.faceCount == 2)
    }

    @Test("Catmull-Clark on triangles produces quads")
    func catmullClarkTriangles() {
        let mesh = Mesh.tetrahedron(attributes: [])
        let subdivided = mesh.catmullClarkSubdivided(iterations: 1)
        // 4 triangular faces × 3 edges each = 12 quads
        #expect(subdivided.faceCount == 12)
        #expect(subdivided.validate() == nil)

        // All faces should be quads (4 vertices)
        for face in subdivided.topology.faces {
            let verts = subdivided.topology.vertexLoop(for: face.id)
            #expect(verts.count == 4)
        }
    }

    @Test("Catmull-Clark two iterations")
    func catmullClarkTwoIterations() {
        let mesh = Mesh.cube(attributes: [])
        let sub1 = mesh.catmullClarkSubdivided(iterations: 1)
        let sub2 = mesh.catmullClarkSubdivided(iterations: 2)
        // After first CC on a cube (6 quads): 24 quads
        // Each quad → 4 quads: 24 × 4 = 96 quads
        #expect(sub1.faceCount == 24)
        #expect(sub2.faceCount == 96)
        #expect(sub2.validate() == nil)
        #expect(sub2.vertexCount - sub2.edgeCount + sub2.faceCount == 2)
    }

    @Test("Catmull-Clark smooths cube toward sphere")
    func catmullClarkSmoothing() {
        let mesh = Mesh.cube(extents: [2, 2, 2], attributes: [])
        let subdivided = mesh.catmullClarkSubdivided(iterations: 3)

        let center = subdivided.center
        let distances = subdivided.positions.map { simd_distance($0, center) }
        let minDist = distances.min()!
        let maxDist = distances.max()!

        // Should be fairly spherical
        let variation = (maxDist - minDist) / ((maxDist + minDist) / 2)
        #expect(variation < 0.15)
    }

    @Test("Catmull-Clark zero iterations returns same mesh")
    func catmullClarkZeroIterations() {
        let mesh = Mesh.cube(attributes: [])
        let result = mesh.catmullClarkSubdivided(iterations: 0)
        #expect(result.faceCount == mesh.faceCount)
        #expect(result.vertexCount == mesh.vertexCount)
    }

    @Test("Catmull-Clark on dodecahedron (pentagons)")
    func catmullClarkDodecahedron() {
        let mesh = Mesh.dodecahedron(attributes: [])
        let subdivided = mesh.catmullClarkSubdivided(iterations: 1)
        // 12 pentagonal faces × 5 = 60 quads
        #expect(subdivided.faceCount == 60)
        #expect(subdivided.validate() == nil)
        #expect(subdivided.vertexCount - subdivided.edgeCount + subdivided.faceCount == 2)
    }
}
