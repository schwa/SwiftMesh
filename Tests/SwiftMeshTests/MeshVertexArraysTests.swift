import GeometryLite3D
import Metal
import MetalSupport
import simd
@testable import SwiftMesh
import Testing

@Suite("Mesh vertex arrays")
struct MeshVertexArraysTests {
    @Test("Corners with the same position and no attributes share a vertex")
    func sharedPositions() {
        let arrays = Mesh.tetrahedron(attributes: []).vertexArrays()
        #expect(arrays.vertexCount == 4)
        #expect(arrays.attributes.map(\.semantic) == [.position])
        #expect(arrays.submeshes.count == 1)
        #expect(arrays.submeshes[0].indices.count == 12)
    }

    @Test("Flat normals split each cube corner into one vertex per face")
    func flatNormalsSplitCorners() {
        let mesh = Mesh.box(extents: [1, 1, 1], attributes: [.flatNormals])
        let arrays = mesh.vertexArrays()
        #expect(arrays.vertexCount == 24)
        #expect(arrays.attributes.map(\.semantic) == [.position, .normal])
        // Each output vertex keeps the position of its source vertex.
        let positions = arrays.attributes[0].bytes.withUnsafeBytes { bytes in
            (0 ..< arrays.vertexCount).map { bytes.loadUnaligned(fromByteOffset: $0 * 12, as: Packed3<Float>.self) }
        }
        for (position, source) in zip(positions, arrays.sourceVertices) {
            #expect(SIMD3(position) == mesh.positions[source.raw])
        }
    }

    @Test("Signed tangents carry the bitangent sign in w")
    func signedTangents() throws {
        let mesh = Mesh.sphere(attributes: [.smoothNormals, .textureCoordinates]).withTangents()
        let cornerTangents = try #require(mesh.signedTangents)
        #expect(cornerTangents.count == mesh.topology.halfEdges.count)
        for (index, tangent) in cornerTangents.enumerated() {
            #expect(abs(tangent.w) == 1)
            let rebuilt = tangent.w * simd_cross(mesh.normals![index], SIMD3(tangent.x, tangent.y, tangent.z))
            #expect(simd_dot(rebuilt, mesh.bitangents![index]) >= 0)
        }
        // Mirroring the mesh flips the sign.
        var mirrored = mesh
        mirrored.bitangents = mesh.bitangents!.map { -$0 }
        #expect(mirrored.signedTangents!.allSatisfy { $0.w == -1 } == cornerTangents.allSatisfy { $0.w == 1 })

        let arrays = mesh.vertexArrays(signedTangents: true)
        #expect(arrays.attributes.map(\.semantic) == [.position, .normal, .texcoord(0), .tangent])
        #expect(arrays.attributes[3].format == .float4)
        #expect(arrays.attributes[3].count == arrays.vertexCount)
    }

    @Test("MetalMesh(mesh:) matches the vertex arrays")
    func metalMeshMatches() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let mesh = Mesh.sphere(attributes: [.smoothNormals, .textureCoordinates])
        let arrays = mesh.vertexArrays()
        let metalMesh = MetalMesh(mesh: mesh, device: device)
        #expect(metalMesh.vertexCount == arrays.vertexCount)
        #expect(metalMesh.vertexDescriptor.attributes.map(\.semantic) == arrays.attributes.map(\.semantic))
        #expect(metalMesh.submeshes.map(\.indices) == arrays.submeshes.map(\.indices))
    }
}
