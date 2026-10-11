import simd
@testable import SwiftMesh
import Testing

@Suite("CornerAttributes")
struct CornerAttributesTests {
    @Test("gathered remaps every present attribute and keeps absent ones nil")
    func gathered() {
        let attributes = CornerAttributes(normals: [[1, 0, 0], [0, 1, 0], [0, 0, 1]], colors: [[1, 0, 0, 1], [0, 1, 0, 1], [0, 0, 1, 1]])
        let result = attributes.gathered([2, 0, 2])
        #expect(result.normals == [[0, 0, 1], [1, 0, 0], [0, 0, 1]])
        #expect(result.colors == [[0, 0, 1, 1], [1, 0, 0, 1], [0, 0, 1, 1]])
        #expect(result.textureCoordinates == nil)
    }

    @Test("concatenated keeps only attributes every part has")
    func concatenated() {
        let a = CornerAttributes(normals: [[1, 0, 0]], textureCoordinates: [[0, 0]])
        let b = CornerAttributes(normals: [[0, 1, 0]])
        let result = CornerAttributes.concatenated([a, b])
        #expect(result.normals == [[1, 0, 0], [0, 1, 0]])
        #expect(result.textureCoordinates == nil)
    }

    @Test("merge carries per-corner attributes of hole loops")
    func mergeWithHoles() {
        let positions: [SIMD3<Float>] = [[0, 0, 0], [4, 0, 0], [4, 4, 0], [0, 4, 0], [1, 1, 0], [1, 3, 0], [3, 3, 0], [3, 1, 0]]
        var mesh = Mesh(positions: positions, faces: [HalfEdgeTopology.FaceDefinition(outer: [0, 1, 2, 3], holes: [[4, 5, 6, 7]])])
        mesh.textureCoordinates = mesh.topology.halfEdges.map { SIMD2(Float($0.origin.raw), 0) }
        let merged = Mesh.merged([mesh, mesh.translated(by: [10, 0, 0])])
        #expect(merged.validate().isEmpty)
        for halfEdge in merged.topology.halfEdges {
            #expect(merged.textureCoordinates![halfEdge.id.raw].x == Float(halfEdge.origin.raw % 8))
        }
    }
}
