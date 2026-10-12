import simd
@testable import SwiftMesh
import Testing

@Suite("Hole filling")
struct HoleFillingTests {
    /// A mesh rebuilt from `mesh` without the given faces.
    private func removing(_ removed: Set<Int>, from mesh: Mesh) -> Mesh {
        let faces = mesh.topology.faces.filter { !removed.contains($0.id.raw) }.map { mesh.topology.vertexLoop(for: $0.id).map(\.raw) }
        return Mesh(positions: mesh.positions, faces: faces)
    }

    @Test("A cube missing one face is closed again, outward and consistent")
    func cube() {
        let open = removing([0], from: .box(attributes: []))
        #expect(open.topology.boundaryLoopCount == 1)
        let filled = open.fillingHoles()
        #expect(filled.faceCount == 6)
        #expect(filled.validate().isEmpty)
        #expect(filled.isManifold)
        #expect(!filled.topology.hasInconsistentFaceWinding)
        let center = filled.center
        #expect(filled.topology.faces.allSatisfy { simd_dot(filled.faceNormal($0.id), filled.faceCentroid($0.id) - center) > 0 })
    }

    @Test("Two holes are both filled")
    func twoHoles() {
        let sphere = Mesh.icoSphere(subdivisions: 1, attributes: [])
        // Two triangles that share no vertex.
        let first = sphere.topology.vertexLoop(for: .init(raw: 0)).map(\.raw)
        let second = sphere.topology.faces.first { face in
            Set(sphere.topology.vertexLoop(for: face.id).map(\.raw)).isDisjoint(with: first)
        }!.id.raw
        let open = removing([0, second], from: sphere)
        #expect(open.topology.boundaryLoopCount == 2)
        let filled = open.fillingHoles()
        #expect(filled.topology.boundaryLoopCount == 0)
        #expect(filled.isManifold)
    }

    @Test("maxEdges leaves larger holes open")
    func maxEdges() {
        let open = removing([0], from: .box(attributes: []))
        #expect(open.fillingHoles(maxEdges: 3).topology.boundaryLoopCount == 1)
        #expect(open.fillingHoles(maxEdges: 4).topology.boundaryLoopCount == 0)
    }

    @Test("Attributes are kept; the new face gets the hole's flat normal")
    func attributes() throws {
        let box = Mesh.box(attributes: [.flatNormals, .textureCoordinates])
        let topFace = box.topology.faces.first { box.faceNormal($0.id).y > 0.99 }!.id.raw
        var open = removing([topFace], from: box)
        open.normals = open.topology.halfEdges.map { _ in SIMD3<Float>(9, 9, 9) }
        open.textureCoordinates = open.topology.halfEdges.map { SIMD2(Float($0.origin.raw), 0) }
        let filled = open.fillingHoles()
        let normals = try #require(filled.normals)
        let uvs = try #require(filled.textureCoordinates)
        #expect(normals.count == filled.topology.halfEdges.count)
        let newFace = filled.topology.faces.last!.id
        for corner in filled.topology.halfEdgeLoop(for: newFace) {
            #expect(simd_distance(normals[corner.raw], [0, 1, 0]) < 1e-5)
            #expect(uvs[corner.raw].x == Float(filled.topology.halfEdges[corner.raw].origin.raw))
        }
    }

    @Test("Closed meshes are returned unchanged")
    func closed() {
        let sphere = Mesh.icoSphere(subdivisions: 1, attributes: [])
        #expect(sphere.fillingHoles() == sphere)
    }
}
