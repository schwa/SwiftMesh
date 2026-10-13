import simd
@testable import SwiftMesh
import Testing

/// Mesh ↔ vertex arrays round trips on the CPU, with no Metal device.
@Suite("Vertex arrays decoding")
struct VertexArraysDecodingTests {
    static func attributedMesh() -> Mesh {
        var mesh = Mesh.sphere(attributes: .all)
        mesh.colors = mesh.topology.halfEdges.map { SIMD4(mesh.positions[$0.origin.raw], 1) }
        mesh.submeshes = [
            .init(label: "top", faces: mesh.topology.faces.prefix(10).map(\.id)),
            .init(label: "rest", faces: mesh.topology.faces.dropFirst(10).map(\.id))
        ]
        return mesh
    }

    @Test("values(as:) pads short formats with zero and truncates long ones")
    func valuesWidening() {
        let data = MetalMesh.VertexAttributeData.positions([[1, 2, 3], [4, 5, 6]])
        #expect(data.values(as: SIMD4<Float>.self) == [[1, 2, 3, 0], [4, 5, 6, 0]])
        #expect(data.values(as: SIMD2<Float>.self) == [[1, 2], [4, 5]])
    }

    @Test("Round trip keeps positions, every corner attribute, and submesh labels", arguments: [false, true])
    func roundTrip(exactTopology: Bool) throws {
        let mesh = Self.attributedMesh()
        let arrays = mesh.vertexArrays()
        let restored = Mesh(vertexArrays: arrays, opposites: exactTopology ? arrays.cornerTable().opposites : nil)

        #expect(restored.validate().isEmpty)
        #expect(restored.faceCount == mesh.triangulated().faceCount)
        #expect(restored.submeshes.map(\.label) == ["top", "rest"])
        #expect(Set(restored.positions) == Set(mesh.positions))
        let corners = restored.topology.halfEdges.count
        for count in [restored.normals?.count, restored.textureCoordinates?.count, restored.tangents?.count, restored.bitangents?.count, restored.colors?.count] {
            #expect(count == corners)
        }
        // Colors encode their corner's position, so each restored corner must match its origin.
        let colors = try #require(restored.colors)
        for halfEdge in restored.topology.halfEdges {
            #expect(SIMD4(restored.positions[halfEdge.origin.raw], 1) == colors[halfEdge.id.raw])
        }
    }

    @Test("Exact topology keeps twins across attribute seams")
    func exactTopologyIsClosed() {
        let mesh = Mesh.box(attributes: .all)
        let arrays = mesh.vertexArrays()
        let table = arrays.cornerTable()
        #expect(!table.opposites.contains(.max))
        #expect(Mesh(vertexArrays: arrays, opposites: table.opposites).isManifold)
    }
}
