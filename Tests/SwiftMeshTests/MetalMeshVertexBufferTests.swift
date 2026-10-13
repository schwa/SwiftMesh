import Metal
@testable import SwiftMesh
import Testing

@Suite("MetalMesh vertex buffers")
struct MetalMeshVertexBufferTests {
    static let positions: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [0, 1, 0]]
    static let uvs: [SIMD2<Float>] = [[0, 1], [1, 1], [0, 0]]
    static let tangents: [SIMD4<Float>] = [[1, 0, 0, 1], [1, 0, 0, -1], [0, 1, 0, 1]]

    func triangle(device: MTLDevice, offset: Float = 0, bufferLayout: MetalMesh.BufferLayout = .interleaved) -> MetalMesh {
        MetalMesh(device: device, attributes: [.positions(Self.positions.map { $0 + offset }), .textureCoordinates(Self.uvs, set: 1), .tangents(Self.tangents)], submeshes: [.init(indices: [0, 1, 2])], bufferLayout: bufferLayout)
    }

    @Test("Attribute data reads back what the array init wrote", arguments: [MetalMesh.BufferLayout.interleaved, .separateBuffers])
    func readBack(_ bufferLayout: MetalMesh.BufferLayout) throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let attributes = triangle(device: device, bufferLayout: bufferLayout).vertexAttributeData()
        let expected: [MetalMesh.VertexAttributeData] = [.positions(Self.positions), .textureCoordinates(Self.uvs, set: 1), .tangents(Self.tangents)]
        #expect(attributes.map(\.semantic) == expected.map(\.semantic))
        #expect(attributes.map(\.format) == expected.map(\.format))
        #expect(attributes.map(\.bytes) == expected.map(\.bytes))
    }

    @Test("Packing shares one vertex buffer and keeps each mesh's vertices")
    func packing() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let meshes = [triangle(device: device), triangle(device: device, offset: 5)]
        let packed = try MetalMesh.packingVertexBuffers(meshes)
        let stride = try #require(meshes[0].vertexDescriptor.layouts[0]?.stride)
        #expect(packed[0].vertexBuffers[0] === packed[1].vertexBuffers[0])
        #expect(packed.map { $0.vertexBufferOffsets[0] } == [0, 3 * stride])
        for (original, repacked) in zip(meshes, packed) {
            #expect(repacked.vertexAttributeData().map(\.bytes) == original.vertexAttributeData().map(\.bytes))
            #expect(repacked.submeshes[0].indexBuffer === original.submeshes[0].indexBuffer)
        }
    }
}
