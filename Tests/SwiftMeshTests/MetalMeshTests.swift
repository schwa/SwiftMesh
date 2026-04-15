import Metal
import simd
@testable import SwiftMesh
import Testing

@Suite("MetalMesh")
struct MetalMeshTests {
    private func requireDevice() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalMeshTestError.noDevice
        }
        return device
    }

    enum MetalMeshTestError: Error {
        case noDevice
    }

    @Test("Triangle mesh produces correct vertex/index counts")
    func triangleCounts() throws {
        let device = try requireDevice()
        let mesh = Mesh.tetrahedron
        let metalMesh = MetalMesh(mesh: mesh, device: device, label: "Tetrahedron")

        // 4 faces × 3 corners = 12 vertices (split per-corner)
        #expect(metalMesh.vertexCount == 12)
        // 1 submesh (no material tags)
        #expect(metalMesh.submeshes.count == 1)
        // 12 indices
        #expect(metalMesh.submeshes[0].indexCount == 12)
    }

    @Test("Octahedron export")
    func octahedron() throws {
        let device = try requireDevice()
        let metalMesh = MetalMesh(mesh: .octahedron, device: device)
        // 8 faces × 3 = 24
        #expect(metalMesh.vertexCount == 24)
        #expect(metalMesh.submeshes.count == 1)
        #expect(metalMesh.submeshes[0].indexCount == 24)
    }

    @Test("Icosahedron export")
    func icosahedron() throws {
        let device = try requireDevice()
        let metalMesh = MetalMesh(mesh: .icosahedron, device: device)
        // 20 faces × 3 = 60
        #expect(metalMesh.vertexCount == 60)
        #expect(metalMesh.submeshes.count == 1)
        #expect(metalMesh.submeshes[0].indexCount == 60)
    }

    @Test("Mesh submeshes produce MetalMesh submeshes")
    func meshSubmeshes() throws {
        let device = try requireDevice()
        let topo = HalfEdgeTopology(vertexCount: 6, faces: [
            .init(outer: [0, 1, 2]),
            .init(outer: [3, 4, 5])
        ])
        let mesh = Mesh(
            topology: topo,
            positions: [
                SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0),
                SIMD3(2, 0, 0), SIMD3(3, 0, 0), SIMD3(2.5, 1, 0)
            ],
            submeshes: [
                .init(label: "A", faces: [topo.faces[0].id]),
                .init(label: "B", faces: [topo.faces[1].id])
            ]
        )
        let metalMesh = MetalMesh(mesh: mesh, device: device)
        #expect(metalMesh.submeshes.count == 2)
        #expect(metalMesh.submeshes[0].indexCount == 3)
        #expect(metalMesh.submeshes[1].indexCount == 3)
    }

    @Test("Label propagates")
    func labelPropagates() throws {
        let device = try requireDevice()
        let metalMesh = MetalMesh(mesh: .tetrahedron, device: device, label: "Test")
        #expect(metalMesh.label == "Test")
        #expect(metalMesh.vertexBuffer.label == "Test Vertices")
    }

    @Test("Cube (quad faces) exports correctly via triangulation")
    func cubeExport() throws {
        let device = try requireDevice()
        let metalMesh = MetalMesh(mesh: .cube, device: device)
        // 6 quad faces × 2 triangles × 3 verts = 36
        #expect(metalMesh.vertexCount == 36)
        #expect(metalMesh.submeshes.count == 1)
        #expect(metalMesh.submeshes[0].indexCount == 36)
    }

    @Test("Dodecahedron (pentagon faces) exports correctly")
    func dodecahedronExport() throws {
        let device = try requireDevice()
        let metalMesh = MetalMesh(mesh: .dodecahedron, device: device)
        // 12 pentagon faces × 3 triangles × 3 verts = 108
        #expect(metalMesh.vertexCount == 108)
        #expect(metalMesh.submeshes.count == 1)
        #expect(metalMesh.submeshes[0].indexCount == 108)
    }
}
