import simd
@testable import SwiftMesh
import Testing

@Suite("Mesh Optimization")
struct MeshOptimizationTests {
    @Test("Merging coplanar faces on a triangulated quad")
    func mergeTriangulatedQuad() {
        // Two coplanar triangles forming a quad
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0)
        ], faces: [[0, 1, 2], [0, 2, 3]])
        #expect(mesh.faceCount == 2)

        let merged = mesh.mergingCoplanarFaces()
        #expect(merged.faceCount == 1)
        #expect(merged.vertexCount == 4)
        #expect(merged.validate() == nil)
    }

    @Test("Non-coplanar faces are not merged")
    func noMergeNonCoplanar() {
        // Two triangles at 90 degrees
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)
        ], faces: [[0, 1, 2], [0, 1, 3]])
        let merged = mesh.mergingCoplanarFaces()
        #expect(merged.faceCount == 2)
    }

    @Test("CSG result benefits from merging")
    func csgMerging() {
        let a = Mesh.box(extents: [1, 1, 1], attributes: [])
        let b = Mesh.box(extents: [0.5, 0.5, 0.5], attributes: [])
        let diff = a.difference(b)
        let merged = diff.mergingCoplanarFaces()
        // Merged should have fewer faces than the raw CSG result
        #expect(merged.faceCount < diff.faceCount)
    }
}
