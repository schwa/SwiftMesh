import simd
@testable import SwiftMesh
import Testing

@Suite("Edge flip")
struct EdgeFlipTests {
    private func makeSquare() -> Mesh {
        var mesh = Mesh(positions: [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]], faces: [[0, 1, 2], [0, 2, 3]])
        mesh.textureCoordinates = mesh.topology.halfEdges.map { halfEdge in
            let position = mesh.positions[halfEdge.origin.raw]
            return SIMD2(position.x, position.y)
        }
        return mesh
    }

    private func diagonal(_ mesh: Mesh) -> Set<Int> {
        let shared = mesh.topology.halfEdges.first { $0.twin != nil }!
        return [shared.origin.raw, mesh.topology.destViaNext(of: shared.id)!.raw]
    }

    @Test("Flipping a square's diagonal swaps it and keeps UVs with their vertices")
    func flipSquare() {
        var mesh = makeSquare()
        #expect(diagonal(mesh) == [0, 2])
        let shared = mesh.topology.halfEdges.first { $0.twin != nil }!.id
        let flipped = mesh.flipEdge(shared)
        #expect(flipped)
        #expect(diagonal(mesh) == [1, 3])
        #expect(mesh.validate().isEmpty)
        #expect(mesh.topology.faces.allSatisfy { mesh.topology.halfEdgeLoop(for: $0.id).count == 3 })
        // Faces still face +z.
        #expect(mesh.topology.faces.allSatisfy { mesh.faceNormal($0.id).z > 0.99 })
        for halfEdge in mesh.topology.halfEdges {
            let position = mesh.positions[halfEdge.origin.raw]
            #expect(mesh.textureCoordinates![halfEdge.id.raw] == SIMD2(position.x, position.y))
        }
    }

    @Test("Boundary edges and existing diagonals are refused")
    func refused() {
        var mesh = makeSquare()
        let boundary = mesh.topology.halfEdges.first { $0.twin == nil }!.id
        let before = mesh
        let flippedBoundary = mesh.flipEdge(boundary)
        #expect(!flippedBoundary)
        #expect(mesh == before)

        // In a tetrahedron the opposite vertices of any edge are already connected.
        var tetrahedron = Mesh.tetrahedron(attributes: [])
        let flippedTetrahedron = tetrahedron.topology.flipEdge(tetrahedron.topology.halfEdges[0].id)
        #expect(!flippedTetrahedron)
    }

    @Test("Flipping on a closed mesh keeps it manifold, and flipping twice restores the edge set")
    func closedMesh() {
        var mesh = Mesh.icoSphere(subdivisions: 1, attributes: [])
        let edges = { (mesh: Mesh) in Set(mesh.topology.undirectedEdges().map { Set([$0.0.raw, $0.1.raw]) }) }
        let original = edges(mesh)
        let target = mesh.topology.halfEdges[5].id
        let first = mesh.flipEdge(target)
        #expect(first)
        #expect(mesh.validate().isEmpty)
        #expect(mesh.isManifold)
        #expect(edges(mesh) != original)
        let second = mesh.flipEdge(target)
        #expect(second)
        #expect(edges(mesh) == original)
    }
}
