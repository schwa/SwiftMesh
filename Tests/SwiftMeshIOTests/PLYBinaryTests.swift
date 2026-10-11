import Foundation
import simd
import SwiftMesh
@testable import SwiftMeshIO
import Testing

@Suite("PLY binary")
struct PLYBinaryTests {
    @Test("Round-trip preserves positions, faces, and normals", arguments: [PLY.Format.ascii, .binaryLittleEndian, .binaryBigEndian])
    func roundTrip(format: PLY.Format) throws {
        let mesh = Mesh.icoSphere(subdivisions: 2, attributes: [.smoothNormals])
        let data = PLY.write(mesh, format: format)
        let loaded = try PLY.read(from: data)
        #expect(loaded.positions == mesh.positions)
        #expect(loaded.faceCount == mesh.faceCount)
        #expect(loaded.topology.faces.map { loaded.topology.vertexLoop(for: $0.id) } == mesh.topology.faces.map { mesh.topology.vertexLoop(for: $0.id) })
        #expect(loaded.normals != nil)
        #expect(loaded.validate().isEmpty)
    }

    @Test("Binary is smaller than ASCII")
    func smaller() {
        let mesh = Mesh.icoSphere(subdivisions: 4, attributes: [])
        #expect(PLY.write(mesh, format: .binaryLittleEndian).count < PLY.write(mesh, format: .ascii).count)
    }

    @Test("Big-endian file with extra properties, ushort lists, and unknown elements")
    func handBuilt() throws {
        var data = Data("""
        ply
        format binary_big_endian 1.0
        comment hand built
        element vertex 3
        property float x
        property uchar red
        property float y
        property float z
        element face 1
        property uchar flags
        property list uchar ushort vertex_index
        element edge 1
        property int vertex1
        property int vertex2
        end_header

        """.utf8)
        func float(_ value: Float) { withUnsafeBytes(of: value.bitPattern.bigEndian) { data.append(contentsOf: $0) } }
        for (x, y, z) in [(Float(0), Float(0), Float(0)), (1, 0, 0), (0, 1, 0)] {
            float(x)
            data.append(255) // red
            float(y)
            float(z)
        }
        data.append(7) // flags
        data.append(3)
        for index: UInt16 in [0, 1, 2] {
            withUnsafeBytes(of: index.bigEndian) { data.append(contentsOf: $0) }
        }
        for value: Int32 in [0, 1] {
            withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
        }

        let mesh = try PLY.read(from: data)
        #expect(mesh.positions == [[0, 0, 0], [1, 0, 0], [0, 1, 0]])
        #expect(mesh.topology.vertexLoop(for: .init(raw: 0)).map(\.raw) == [0, 1, 2])
        #expect(mesh.normals == nil)
    }

    @Test("Truncated binary body throws")
    func truncated() {
        let data = PLY.write(Mesh.cube(attributes: []), format: .binaryLittleEndian)
        #expect(throws: PLYError.self) {
            try PLY.read(from: data.dropLast(5))
        }
    }
}
