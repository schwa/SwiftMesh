import Metal
@testable import SwiftMesh
import Testing

@Suite("MetalMesh index buffer merging")
struct MetalMeshMergingTests {
    func twoSubmeshMesh(device: MTLDevice) -> MetalMesh {
        let positions: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0]]
        return MetalMesh(device: device, attributes: [.positions(positions)], submeshes: [.init(label: "A", indices: [0, 1, 2]), .init(label: "B", indices: [1, 3, 2])])
    }

    @Test("Each submesh gets its own index buffer at offset 0")
    func separateByDefault() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let mesh = twoSubmeshMesh(device: device)
        #expect(mesh.submeshes[0].indexBuffer !== mesh.submeshes[1].indexBuffer)
        #expect(mesh.submeshes.map(\.indexBufferOffset) == [0, 0])
        #expect(mesh.submeshes.map(\.indices) == [[0, 1, 2], [1, 3, 2]])

        let fromMesh = MetalMesh(mesh: .box(extents: [1, 1, 1], attributes: []), device: device)
        #expect(fromMesh.submeshes.allSatisfy { $0.indexBufferOffset == 0 })
    }

    @Test("Merging shares one index buffer and keeps each submesh's indices")
    func merging() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let mesh = twoSubmeshMesh(device: device)
        let merged = try mesh.mergingIndexBuffers()
        #expect(merged.submeshes[0].indexBuffer === merged.submeshes[1].indexBuffer)
        #expect(merged.submeshes.map(\.indexBufferOffset) == [0, 3 * MemoryLayout<UInt32>.stride])
        #expect(merged.submeshes.map(\.indices) == [[0, 1, 2], [1, 3, 2]])
        #expect(merged.submeshes.map(\.label) == ["A", "B"])
        #expect(merged.vertexBuffers[0] === mesh.vertexBuffers[0])
    }
}
