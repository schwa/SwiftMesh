import simd
@testable import SwiftMesh
import Testing

@Suite("TriangleSoup")
struct TriangleSoupTests {
    // MARK: - Construction

    @Test("Empty soup")
    func emptySoup() {
        let soup = TriangleSoup()
        #expect(soup.triangleCount == 0)
        #expect(soup.positionCount == 0)
    }

    @Test("Add triangle by positions")
    func addTriangle() {
        var soup = TriangleSoup()
        soup.addTriangle(SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0))
        #expect(soup.triangleCount == 1)
        #expect(soup.positionCount == 3)
    }

    @Test("Append two soups")
    func appendSoups() {
        var a = TriangleSoup()
        a.addTriangle(SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0))

        var b = TriangleSoup()
        b.addTriangle(SIMD3(2, 0, 0), SIMD3(3, 0, 0), SIMD3(2, 1, 0))

        a.append(b)
        #expect(a.triangleCount == 2)
        #expect(a.positionCount == 6)
        // Second triangle indices should be offset
        #expect(a.triangles[1].0 == 3)
        #expect(a.triangles[1].1 == 4)
        #expect(a.triangles[1].2 == 5)
    }

    // MARK: - Welding

    @Test("Weld merges duplicate positions")
    func weldDuplicates() {
        // Two triangles sharing an edge (positions duplicated)
        var soup = TriangleSoup()
        soup.addTriangle(SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0))
        soup.addTriangle(SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0))
        #expect(soup.positionCount == 6)

        let welded = soup.welded()
        #expect(welded.positionCount == 4)
        #expect(welded.triangleCount == 2)
    }

    @Test("Weld preserves distinct positions")
    func weldDistinct() {
        var soup = TriangleSoup()
        soup.addTriangle(SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0))
        soup.addTriangle(SIMD3(10, 10, 10), SIMD3(11, 10, 10), SIMD3(10, 11, 10))

        let welded = soup.welded()
        #expect(welded.positionCount == 6)
    }

    // MARK: - Flipping

    @Test("Flip reverses winding")
    func flipWinding() {
        var soup = TriangleSoup()
        soup.addTriangle(SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0))

        let original = soup.triangles[0]
        soup.flipAll()
        let flipped = soup.triangles[0]

        #expect(flipped.0 == original.0)
        #expect(flipped.1 == original.2)
        #expect(flipped.2 == original.1)
    }

    // MARK: - Mesh round-trip

    @Test("Mesh → TriangleSoup → Mesh round-trip preserves triangle count")
    func meshRoundTrip() {
        let mesh = Mesh.tetrahedron(attributes: [])
        let soup = TriangleSoup(mesh: mesh)
        #expect(soup.triangleCount == 4) // tetrahedron has 4 triangular faces

        let result = soup.toMesh()
        #expect(result.faceCount == 4)
        #expect(result.vertexCount == 4)
        #expect(result.validate().isEmpty)
    }

    @Test("Cube triangulation produces 12 triangles")
    func cubeTriangulation() {
        let mesh = Mesh.cube(attributes: [])
        let soup = TriangleSoup(mesh: mesh)
        #expect(soup.triangleCount == 12) // 6 quad faces → 12 triangles
    }

    @Test("Round-trip degenerate triangles are filtered")
    func degenerateFiltered() {
        // Create a soup with a degenerate triangle (two identical positions that will weld)
        var soup = TriangleSoup()
        soup.positions = [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 0)]
        soup.triangles = [
            (0, 1, 2),  // valid
            (0, 3, 1)  // after welding, index 3 → 0, making this (0, 0, 1) — degenerate
        ]
        let mesh = soup.toMesh()
        #expect(mesh.faceCount == 1) // degenerate triangle should be filtered
    }
}
