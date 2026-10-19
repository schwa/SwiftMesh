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
        let center = (mesh.bounds!.min + mesh.bounds!.max) / 2
        for face in mesh.topology.faces where face.edge != nil {
            #expect(simd_dot(mesh.faceNormal(face.id), mesh.faceCentroid(face.id) - center) > 0, "\(name) face \(face.id)")
        }
    }

    /// Closed primitives with a point known to be inside the solid (catches non-convex shapes).
    static let closedSolids: [(String, Mesh, SIMD3<Float>)] = convexSolids.map { ($0.0, $0.1, SIMD3<Float>(0.0013, 0.0011, 0.0007)) } + [
        ("torus", .torus(), [0.3011, 0.0013, 0.0007]),
        ("hemisphere", .hemisphere(), [0.0013, 0.1011, 0.0007])
    ]

    @Test("Closed primitives wind +1 around an interior point", arguments: closedSolids.map(\.0))
    func interiorWinding(name: String) throws {
        let (_, mesh, inside) = Self.closedSolids.first { $0.0 == name }!
        let winding = try #require(mesh.windingNumbers(at: [inside]))
        #expect(winding == [1])
    }

    @Test("Torus faces point away from the tube's centerline; hemisphere faces away from its center")
    func nonConvexOutward() {
        let torus = Mesh.torus(attributes: [])
        for face in torus.topology.faces {
            let centroid = torus.faceCentroid(face.id)
            let ring = simd_normalize(SIMD3(centroid.x, 0, centroid.z)) * 0.3 // default major radius
            #expect(simd_dot(torus.faceNormal(face.id), centroid - ring) > 0)
        }
        let hemisphere = Mesh.hemisphere(attributes: [])
        let center = SIMD3<Float>(0, 0.25, 0) // inside the dome, above the cap
        for face in hemisphere.topology.faces {
            #expect(simd_dot(hemisphere.faceNormal(face.id), hemisphere.faceCentroid(face.id) - center) > 0)
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
