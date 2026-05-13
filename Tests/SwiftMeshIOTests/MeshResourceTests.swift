import Foundation
import RealityKit
import simd
@testable import SwiftMesh
@testable import SwiftMeshIO
import Testing

@Suite("Mesh → MeshResource")
@MainActor
struct MeshResourceTests {
    @Test("Convert a positions-only triangle")
    func convertTriangle() throws {
        let mesh = Mesh(
            positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0)],
            faces: [[0, 1, 2]]
        )

        let resource = try MeshResource.generate(from: mesh)

        #expect(!resource.contents.models.isEmpty)
        let model = resource.contents.models.map(\.self).first!
        #expect(!model.parts.isEmpty)
    }

    @Test("Convert a cube with submeshes preserves part names")
    func convertCubeWithLabels() throws {
        var mesh = Mesh.cube(extents: [1, 1, 1])
        // Replace the default single-submesh layout with one labeled submesh
        // per face so we can check name round-tripping.
        let perFace = mesh.topology.faces.enumerated().map { idx, face in
            Mesh.Submesh(label: "face_\(idx)", faces: [face.id])
        }
        mesh.submeshes = perFace

        let resource = try MeshResource.generate(from: mesh)
        let model = resource.contents.models.map(\.self).first!

        let partIDs = Set(model.parts.map(\.id))
        for idx in mesh.submeshes.indices {
            #expect(partIDs.contains("face_\(idx)"))
        }
    }

    @Test("Convert mesh with normals + UVs")
    func convertWithAttributes() throws {
        let mesh = Mesh.cube(extents: [1, 1, 1], attributes: .default)
            .withFlatNormals()
            .withSphericalUVs()

        let resource = try MeshResource.generate(from: mesh, generateTangentsIfMissing: false)
        let model = resource.contents.models.map(\.self).first!
        for part in model.parts {
            #expect(part.positions.count > 0)
            // swiftlint:disable:previous empty_count -- MeshBuffer lacks `isEmpty`
            #expect(part.normals != nil)
            #expect(part.textureCoordinates != nil)
        }
    }

    @Test("Generates tangents when missing if requested")
    func generatesTangents() throws {
        let mesh = Mesh.cube(extents: [1, 1, 1], attributes: .default)
            .withFlatNormals()
            .withSphericalUVs()

        let resource = try MeshResource.generate(from: mesh, generateTangentsIfMissing: true)
        let model = resource.contents.models.map(\.self).first!
        for part in model.parts {
            #expect(part.tangents != nil)
        }
    }

    @Test("Empty mesh throws")
    func emptyMeshThrows() {
        let empty = Mesh(positions: [], faces: [] as [[Int]])
        #expect(throws: MeshResourceConversionError.self) {
            _ = try MeshResource.generate(from: empty)
        }
    }

    @Test("N-gon faces are triangulated")
    func quadIsTriangulated() throws {
        // A single quad (4-vertex face).
        let mesh = Mesh(
            positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0)],
            faces: [[0, 1, 2, 3]]
        )
        let resource = try MeshResource.generate(from: mesh)
        let model = resource.contents.models.map(\.self).first!
        let part = model.parts.map(\.self).first!
        // 1 quad → 2 triangles → 6 indices
        let triCount = part.triangleIndices?.count ?? 0
        #expect(triCount == 6)
    }
}
