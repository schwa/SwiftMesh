import simd
@testable import SwiftMesh
import Testing

@Suite("Face extrude")
struct FaceExtrudeTests {
    @Test("Extruding a box face adds four walls and stays a closed manifold")
    func extrudeBoxFace() {
        let box = Mesh.box(attributes: [.flatNormals])
        let face = HalfEdgeTopology.FaceID(raw: 0)
        let normal = box.faceNormal(face)
        let centroid = box.faceCentroid(face)
        let mesh = box.extrudingFace(face, distance: 0.5)

        #expect(mesh.faceCount == box.faceCount + 4)
        #expect(mesh.vertexCount == box.vertexCount + 4)
        #expect(mesh.validate().isEmpty)
        #expect(mesh.isManifold)
        #expect(simd_distance(mesh.faceCentroid(face), centroid + normal * 0.5) < 1e-6)
        #expect(simd_distance(mesh.faceNormal(face), normal) < 1e-6)

        // Every face points away from the solid's center.
        let center = mesh.center
        for meshFace in mesh.topology.faces {
            #expect(simd_dot(mesh.faceNormal(meshFace.id), mesh.faceCentroid(meshFace.id) - center) > 0)
        }
        // Wall corner normals match the wall's geometric normal.
        for wall in box.faceCount..<mesh.faceCount {
            let wallID = HalfEdgeTopology.FaceID(raw: wall)
            for corner in mesh.topology.halfEdgeLoop(for: wallID) {
                #expect(simd_distance(mesh.normals![corner.raw], mesh.faceNormal(wallID)) < 1e-5)
            }
        }
        #expect(mesh.submeshes.flatMap(\.faces).count == mesh.faceCount)
    }

    @Test("Extruding an open quad creates walls with a boundary at the base")
    func extrudeOpenQuad() {
        let quad = Mesh(positions: [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]], faces: [[0, 1, 2, 3]])
        let mesh = quad.extrudingFace(.init(raw: 0), distance: 1)
        #expect(mesh.faceCount == 5)
        #expect(mesh.validate().isEmpty)
        #expect(mesh.topology.boundaryLoops().count == 1)
        #expect(mesh.faceCentroid(.init(raw: 0)) == [0.5, 0.5, 1])
    }
}
