import simd
@testable import SwiftMesh
import Testing

@Suite("Smooth normals with a crease angle")
struct CreaseAngleNormalsTests {
    static let smooth: MeshAttributes = [.smoothNormals]

    /// Corners whose normal is not their face's normal.
    static func smoothedCornerCount(_ mesh: Mesh) -> Int {
        let normals = mesh.normals!
        var count = 0
        for face in mesh.topology.faces {
            let faceNormal = mesh.faceNormal(face.id)
            for corner in mesh.topology.halfEdgeLoop(for: face.id) where simd_dot(normals[corner.raw], faceNormal) < 0.9999 {
                count += 1
            }
        }
        return count
    }

    @Test("Cylinder caps stay flat")
    func cylinderCapsFlat() throws {
        let mesh = Mesh.cylinder(segments: 16, attributes: Self.smooth)
        let normals = try #require(mesh.normals)
        for face in mesh.topology.faces where abs(mesh.faceNormal(face.id).y) > 0.99 {
            for corner in mesh.topology.halfEdgeLoop(for: face.id) {
                #expect(simd_distance(normals[corner.raw], mesh.faceNormal(face.id)) < 1e-5)
            }
        }
        // The sides are still smooth: no side corner points straight out of its own face.
        #expect(Self.smoothedCornerCount(mesh) == 16 * 4)
    }

    @Test("Cone side corners at the apex lean toward their own face")
    func coneApex() throws {
        let mesh = Mesh.cone(segments: 32, attributes: Self.smooth)
        let normals = try #require(mesh.normals)
        let apex = mesh.positions.indices.max { mesh.positions[$0].y < mesh.positions[$1].y }!
        for face in mesh.topology.faces where abs(mesh.faceNormal(face.id).y) < 0.99 {
            for corner in mesh.topology.halfEdgeLoop(for: face.id) where mesh.topology.halfEdges[corner.raw].origin.raw == apex {
                #expect(simd_dot(normals[corner.raw], mesh.faceNormal(face.id)) > 0.7)
            }
        }
    }

    @Test("A sphere is smooth everywhere")
    func sphereSmooth() throws {
        let creased = Mesh.sphere(attributes: Self.smooth)
        let uncreased = Mesh.sphere(attributes: []).withSmoothNormals()
        #expect(creased.normals?.count == uncreased.normals?.count)
        for (a, b) in zip(try #require(creased.normals), try #require(uncreased.normals)) {
            #expect(simd_distance(a, b) < 1e-4)
        }
    }

    @Test("A crease angle of 180 degrees matches plain smoothing")
    func straightAngleMatches() throws {
        let mesh = Mesh.box(attributes: [])
        let creased = try #require(mesh.withSmoothNormals(creaseAngle: .pi).normals)
        let plain = try #require(mesh.withSmoothNormals().normals)
        for (a, b) in zip(creased, plain) {
            #expect(simd_distance(a, b) < 1e-5)
        }
    }

    @Test("A box keeps every edge hard")
    func boxHard() {
        #expect(Self.smoothedCornerCount(Mesh.box(attributes: Self.smooth)) == 0)
    }
}
