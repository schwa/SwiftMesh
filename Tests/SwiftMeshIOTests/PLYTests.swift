import Foundation
import simd
@testable import SwiftMesh
@testable import SwiftMeshIO
import Testing

@Suite("PLY I/O")
struct PLYTests {
    // MARK: - Reading

    @Test("Read triangle")
    func readTriangle() throws {
        let ply = """
        ply
        format ascii 1.0
        element vertex 3
        property float x
        property float y
        property float z
        element face 1
        property list uchar int vertex_indices
        end_header
        0 0 0
        1 0 0
        0.5 1 0
        3 0 1 2
        """
        let mesh = try PLY.read(from: ply)
        #expect(mesh.vertexCount == 3)
        #expect(mesh.faceCount == 1)
        #expect(mesh.validate() == nil)
        #expect(mesh.positions[0] == SIMD3(0, 0, 0))
        #expect(mesh.positions[1] == SIMD3(1, 0, 0))
    }

    @Test("Read quad")
    func readQuad() throws {
        let ply = """
        ply
        format ascii 1.0
        element vertex 4
        property float x
        property float y
        property float z
        element face 1
        property list uchar int vertex_indices
        end_header
        0 0 0
        1 0 0
        1 1 0
        0 1 0
        4 0 1 2 3
        """
        let mesh = try PLY.read(from: ply)
        #expect(mesh.vertexCount == 4)
        #expect(mesh.faceCount == 1)
        let loop = mesh.topology.vertexLoop(for: mesh.topology.faces[0].id)
        #expect(loop.count == 4)
    }

    @Test("Read with normals")
    func readWithNormals() throws {
        let ply = """
        ply
        format ascii 1.0
        element vertex 3
        property float x
        property float y
        property float z
        property float nx
        property float ny
        property float nz
        element face 1
        property list uchar int vertex_indices
        end_header
        0 0 0 0 0 1
        1 0 0 0 0 1
        0.5 1 0 0 0 1
        3 0 1 2
        """
        let mesh = try PLY.read(from: ply)
        #expect(mesh.normals != nil)
        #expect(mesh.normals!.count == mesh.topology.halfEdges.count)
        // All normals should be (0,0,1)
        for normal in mesh.normals! {
            #expect(abs(normal.z - 1.0) < 1e-5)
        }
    }

    @Test("Read with comments")
    func readWithComments() throws {
        let ply = """
        ply
        format ascii 1.0
        comment This is a test
        element vertex 3
        property float x
        property float y
        property float z
        comment Another comment
        element face 1
        property list uchar int vertex_indices
        end_header
        0 0 0
        1 0 0
        0 1 0
        3 0 1 2
        """
        let mesh = try PLY.read(from: ply)
        #expect(mesh.vertexCount == 3)
    }

    @Test("Read fails on missing magic")
    func readFailsMagic() {
        #expect(throws: PLYError.self) {
            try PLY.read(from: "not a ply file")
        }
    }

    @Test("Read fails on binary format")
    func readFailsBinary() {
        let ply = """
        ply
        format binary_little_endian 1.0
        element vertex 0
        element face 0
        end_header
        """
        #expect(throws: PLYError.self) {
            try PLY.read(from: ply)
        }
    }

    // MARK: - Writing

    @Test("Write triangle")
    func writeTriangle() {
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0)
        ], faces: [[0, 1, 2]])

        let data = PLY.write(mesh)
        let string = String(data: data, encoding: .utf8)!

        #expect(string.hasPrefix("ply\n"))
        #expect(string.contains("element vertex 3"))
        #expect(string.contains("element face 1"))
        #expect(string.contains("3 0 1 2"))
    }

    @Test("Write with normals")
    func writeWithNormals() {
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0)
        ], faces: [[0, 1, 2]]).withFlatNormals()

        let data = PLY.write(mesh)
        let string = String(data: data, encoding: .utf8)!

        #expect(string.contains("property float nx"))
        #expect(string.contains("property float ny"))
        #expect(string.contains("property float nz"))
    }

    // MARK: - Round-trip

    @Test("Round-trip triangle")
    func roundTripTriangle() throws {
        let original = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0)
        ], faces: [[0, 1, 2]])

        let data = PLY.write(original)
        let restored = try PLY.read(from: data)

        #expect(restored.vertexCount == original.vertexCount)
        #expect(restored.faceCount == original.faceCount)
        for idx in 0..<original.positions.count {
            #expect(abs(restored.positions[idx].x - original.positions[idx].x) < 1e-4)
            #expect(abs(restored.positions[idx].y - original.positions[idx].y) < 1e-4)
            #expect(abs(restored.positions[idx].z - original.positions[idx].z) < 1e-4)
        }
    }

    @Test("Round-trip cube")
    func roundTripCube() throws {
        let data = PLY.write(.cube(attributes: []))
        let restored = try PLY.read(from: data)
        #expect(restored.vertexCount == Mesh.cube(attributes: []).vertexCount)
        #expect(restored.faceCount == Mesh.cube(attributes: []).faceCount)
        #expect(restored.validate() == nil)
    }

    @Test("Round-trip with normals")
    func roundTripNormals() throws {
        let original = Mesh.tetrahedron(attributes: []).withFlatNormals()
        let data = PLY.write(original)
        let restored = try PLY.read(from: data)

        #expect(restored.normals != nil)
        #expect(restored.vertexCount == original.vertexCount)
    }
}
