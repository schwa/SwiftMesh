import simd
@testable import SwiftMesh
import Testing

@Suite("Edge split")
struct EdgeSplitTests {
    @Test("Splitting an interior edge of a closed mesh yields four faces from two and stays manifold")
    func interiorEdge() throws {
        var mesh = Mesh.icoSphere(subdivisions: 1, attributes: [.flatNormals, .textureCoordinates])
        let faceCount = mesh.faceCount
        let vertexCount = mesh.vertexCount
        let edge = mesh.topology.halfEdges[0]
        let origin = mesh.positions[edge.origin.raw]
        let destination = mesh.positions[try #require(mesh.topology.destViaNext(of: edge.id)).raw]

        let split = mesh.splitEdge(edge.id)
        let middle = try #require(split)

        #expect(mesh.faceCount == faceCount + 2)
        #expect(mesh.vertexCount == vertexCount + 1)
        #expect(mesh.validate().isEmpty)
        #expect(mesh.isManifold)
        #expect(simd_distance(mesh.positions[middle.raw], (origin + destination) / 2) < 1e-6)
        #expect(mesh.topology.faces.allSatisfy { mesh.topology.halfEdgeLoop(for: $0.id).count == 3 })
        #expect(mesh.submeshes.flatMap(\.faces).count == mesh.faceCount)
    }

    @Test("Splitting a boundary edge splits only its face")
    func boundaryEdge() throws {
        var mesh = Mesh(positions: [[0, 0, 0], [1, 0, 0], [0, 1, 0]], faces: [[0, 1, 2]])
        mesh.textureCoordinates = [[0, 0], [1, 0], [0, 1]]
        let edge = try #require(mesh.topology.halfEdges.first { $0.origin.raw == 0 })
        let split = mesh.splitEdge(edge.id, at: 0.25)
        let middle = try #require(split)
        #expect(mesh.faceCount == 2)
        #expect(mesh.validate().isEmpty)
        #expect(mesh.positions[middle.raw] == [0.25, 0, 0])
        let middleCorners = mesh.topology.halfEdges.filter { $0.origin == middle }.map { mesh.textureCoordinates![$0.id.raw] }
        #expect(middleCorners.allSatisfy { $0 == [0.25, 0] })
    }

    @Test("Splitting a quad's edge inserts the vertex without splitting the face")
    func quadEdge() throws {
        var mesh = Mesh(positions: [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]], faces: [[0, 1, 2, 3]])
        #expect(mesh.splitEdge(mesh.topology.halfEdges[0].id) != nil)
        #expect(mesh.faceCount == 1)
        #expect(mesh.topology.halfEdgeLoop(for: .init(raw: 0)).count == 5)
        #expect(mesh.validate().isEmpty)
    }
}
