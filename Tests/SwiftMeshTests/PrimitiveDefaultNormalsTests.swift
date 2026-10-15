import simd
@testable import SwiftMesh
import Testing

@Suite("Primitive default normals")
struct PrimitiveDefaultNormalsTests {
    /// True when corners around at least one vertex disagree on their normal, i.e. the mesh is shaded flat.
    /// A cone apex is sharp by design, so vertices at `ignoringY` are skipped.
    static func hasFacetedVertex(_ mesh: Mesh, ignoringY: Float? = nil) -> Bool {
        var normalByVertex: [Int: SIMD3<Float>] = [:]
        for halfEdge in mesh.topology.halfEdges where halfEdge.face != nil {
            if let ignoringY, abs(mesh.positions[halfEdge.origin.raw].y - ignoringY) < 1e-5 {
                continue
            }
            let normal = mesh.normals![halfEdge.id.raw]
            if let seen = normalByVertex[halfEdge.origin.raw], simd_distance(seen, normal) > 1e-4 {
                return true
            }
            normalByVertex[halfEdge.origin.raw] = normal
        }
        return false
    }

    @Test("Curved primitives without caps default to smooth normals")
    func curvedDefaultsSmooth() {
        let meshes: [(String, Mesh)] = [
            ("sphere", .sphere()),
            ("icoSphere", .icoSphere()),
            ("cubeSphere", .cubeSphere()),
            ("torus", .torus()),
            ("capsule", .capsule()),
            ("cylinder", .cylinder(capped: false)),
            ("conicalFrustum", .conicalFrustum(capped: false)),
            ("hemisphere", .hemisphere(capped: false))
        ]
        let faceted = meshes.filter { Self.hasFacetedVertex($0.1) }.map(\.0)
        #expect(faceted.isEmpty)
        #expect(meshes.allSatisfy { $0.1.textureCoordinates != nil })

        let cone = Mesh.cone(capped: false)
        #expect(!Self.hasFacetedVertex(cone, ignoringY: cone.bounds.max.y))
    }

    @Test("Flat-faced primitives default to flat normals", arguments: [
        ("cube", Mesh.cube()),
        ("box", Mesh.box()),
        ("octahedron", Mesh.octahedron())
    ])
    func flatDefaultsFlat(name: String, mesh: Mesh) {
        #expect(Self.hasFacetedVertex(mesh), "\(name)")
    }
}
