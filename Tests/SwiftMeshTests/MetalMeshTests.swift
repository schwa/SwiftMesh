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
        let mesh = Mesh.tetrahedron(attributes: [])
        let metalMesh = MetalMesh(mesh: mesh, device: device, label: "Tetrahedron")

        // 4 unique positions shared across 4 faces → 4 deduplicated vertices
        #expect(metalMesh.vertexCount == 4)
        // 1 submesh (no material tags)
        #expect(metalMesh.submeshes.count == 1)
        // 4 faces × 3 = 12 indices
        #expect(metalMesh.submeshes[0].indexCount == 12)
    }

    @Test("Octahedron export")
    func octahedron() throws {
        let device = try requireDevice()
        let metalMesh = MetalMesh(mesh: .octahedron(attributes: []), device: device)
        // 6 unique positions → 6 deduplicated vertices, 8 faces × 3 = 24 indices
        #expect(metalMesh.vertexCount == 6)
        #expect(metalMesh.submeshes.count == 1)
        #expect(metalMesh.submeshes[0].indexCount == 24)
    }

    @Test("Icosahedron export")
    func icosahedron() throws {
        let device = try requireDevice()
        let metalMesh = MetalMesh(mesh: .icosahedron(attributes: []), device: device)
        // 12 unique positions → 12 deduplicated vertices, 20 faces × 3 = 60 indices
        #expect(metalMesh.vertexCount == 12)
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
        let metalMesh = MetalMesh(mesh: .tetrahedron(attributes: []), device: device, label: "Test")
        #expect(metalMesh.label == "Test")
        #expect(metalMesh.vertexBuffer.label == "Test Vertices")
    }

    @Test("Cube (quad faces) exports correctly via triangulation")
    func cubeExport() throws {
        let device = try requireDevice()
        let metalMesh = MetalMesh(mesh: .cube(attributes: []), device: device)
        // 8 unique positions → 8 deduplicated vertices, 6 × 2 × 3 = 36 indices
        #expect(metalMesh.vertexCount == 8)
        #expect(metalMesh.submeshes.count == 1)
        #expect(metalMesh.submeshes[0].indexCount == 36)
    }

    @Test("Dodecahedron (pentagon faces) exports correctly")
    func dodecahedronExport() throws {
        let device = try requireDevice()
        let metalMesh = MetalMesh(mesh: .dodecahedron(attributes: []), device: device)
        // 20 unique positions → 20 deduplicated vertices, 12 × 3 × 3 = 108 indices
        #expect(metalMesh.vertexCount == 20)
        #expect(metalMesh.submeshes.count == 1)
        #expect(metalMesh.submeshes[0].indexCount == 108)
    }

    @Test("Shared vertices are deduplicated for adjacent triangles")
    func sharedVertices() throws {
        let device = try requireDevice()
        // Two triangles sharing edge (1,2): vertices 0,1,2,3
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0), SIMD3(0.5, -1, 0)
        ], faces: [[0, 1, 2], [1, 0, 3]])
        let metalMesh = MetalMesh(mesh: mesh, device: device)
        // 4 unique positions → 4 vertices, 2 × 3 = 6 indices
        #expect(metalMesh.vertexCount == 4)
        #expect(metalMesh.submeshes[0].indexCount == 6)
    }

    @Test("Flat normals prevent vertex sharing at hard edges")
    func flatNormalsPreventSharing() throws {
        let device = try requireDevice()
        // Two coplanar triangles with flat normals — shared edge vertices have
        // identical normals so they should still be deduplicated
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0), SIMD3(0.5, -1, 0)
        ], faces: [[0, 1, 2], [1, 0, 3]]).withFlatNormals()
        let metalMesh = MetalMesh(mesh: mesh, device: device)
        // Coplanar faces have the same normal, so shared vertices still deduplicate
        #expect(metalMesh.vertexCount == 4)

        // Non-coplanar: tetrahedron with flat normals — every face has a different
        // normal, so shared vertices get split
        let tetraMesh = Mesh.tetrahedron(attributes: []).withFlatNormals()
        let tetraMetal = MetalMesh(mesh: tetraMesh, device: device)
        // Each vertex appears in 3 faces with 3 different normals → 12 unique vertices
        #expect(tetraMetal.vertexCount == 12)
        #expect(tetraMetal.submeshes[0].indexCount == 12)
    }

    // MARK: - MetalMesh → Mesh round-trip

    @Test("Round-trip position-only mesh preserves topology")
    func roundTripPositionOnly() throws {
        let device = try requireDevice()
        let original = Mesh.tetrahedron(attributes: [])
        let metalMesh = MetalMesh(mesh: original, device: device)
        let restored = metalMesh.toMesh()

        #expect(restored.vertexCount == original.vertexCount)
        #expect(restored.faceCount == original.faceCount)
        #expect(restored.validate() == nil)
    }

    @Test("Round-trip preserves normals")
    func roundTripNormals() throws {
        let device = try requireDevice()
        let original = Mesh.cube(attributes: []).withFlatNormals()
        let metalMesh = MetalMesh(mesh: original, device: device)
        let restored = metalMesh.toMesh()

        #expect(restored.normals != nil)
        #expect(restored.validate() == nil)
        // All restored normals should be unit length
        for n in restored.normals! {
            let len = simd_length(n)
            #expect(abs(len - 1.0) < 1e-4)
        }
    }

    @Test("Round-trip preserves UVs")
    func roundTripUVs() throws {
        let device = try requireDevice()
        let original = Mesh.sphere(latitudeSegments: 4, longitudeSegments: 8, attributes: .textureCoordinates)
        let metalMesh = MetalMesh(mesh: original, device: device)
        let restored = metalMesh.toMesh()

        #expect(restored.textureCoordinates != nil)
        #expect(restored.validate() == nil)
        // UV values should be in [0,1]
        for uv in restored.textureCoordinates! {
            #expect(uv.x >= -1e-5 && uv.x <= 1.0 + 1e-5)
            #expect(uv.y >= -1e-5 && uv.y <= 1.0 + 1e-5)
        }
    }

    @Test("Round-trip preserves submeshes")
    func roundTripSubmeshes() throws {
        let device = try requireDevice()
        let topo = HalfEdgeTopology(vertexCount: 6, faces: [
            .init(outer: [0, 1, 2]),
            .init(outer: [3, 4, 5])
        ])
        let original = Mesh(
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
        let metalMesh = MetalMesh(mesh: original, device: device)
        let restored = metalMesh.toMesh()

        #expect(restored.submeshes.count == 2)
        #expect(restored.submeshes[0].faces.count == 1)
        #expect(restored.submeshes[1].faces.count == 1)
        #expect(restored.validate() == nil)
    }
}
