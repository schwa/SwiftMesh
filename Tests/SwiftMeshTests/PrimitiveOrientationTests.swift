import simd
@testable import SwiftMesh
import Testing

// Automated part of the demo-gallery review (#83): catches inside-out faces and flipped normals.
@Suite("Primitive orientation")
struct PrimitiveOrientationTests {
    static let convexSolids: [(String, Mesh)] = [
        ("tetrahedron", .tetrahedron()), ("cube", .cube()), ("octahedron", .octahedron()),
        ("icosahedron", .icosahedron()), ("dodecahedron", .dodecahedron()), ("box", .box()),
        ("sphere", .sphere()), ("icoSphere", .icoSphere()), ("cubeSphere", .cubeSphere()),
        ("cylinder", .cylinder()), ("capsule", .capsule()), ("cone", .cone()),
        ("conicalFrustum", .conicalFrustum()), ("rectangularFrustum", .rectangularFrustum())
    ]

    static let all: [(String, Mesh)] = convexSolids + [
        ("triangle", .triangle()), ("quad", .quad()), ("circle", .circle()),
        ("torus", .torus()), ("hemisphere", .hemisphere()), ("teapot", .teapot())
    ]

    @Test("Convex solids have faces pointing away from their center", arguments: convexSolids.map(\.0))
    func outwardFaces(name: String) {
        let mesh = Self.convexSolids.first { $0.0 == name }!.1
        let center = (mesh.bounds.min + mesh.bounds.max) / 2
        for face in mesh.topology.faces where face.edge != nil {
            #expect(simd_dot(mesh.faceNormal(face.id), mesh.faceCentroid(face.id) - center) > 0, "\(name) face \(face.id)")
        }
    }

    @Test("Corner normals agree with face winding", arguments: all.map(\.0))
    func normalsMatchWinding(name: String) throws {
        let mesh = Self.all.first { $0.0 == name }!.1
        let normals = try #require(mesh.normals)
        var flipped = 0
        for face in mesh.topology.faces where face.edge != nil {
            let faceNormal = mesh.faceNormal(face.id)
            for corner in mesh.topology.halfEdgeLoop(for: face.id) where simd_dot(normals[corner.raw], faceNormal) < 0 {
                flipped += 1
            }
        }
        #expect(flipped == 0, "\(name): \(flipped) corner normals oppose their face")
    }
}
