import simd
@testable import SwiftMesh
import Testing

@Suite("Boolean mesh core")
struct BooleanMeshTests {
    @Test("Closed primitives convert, including ones with attribute seams", arguments: ["cube", "icoSphere", "sphere", "torus", "cylinder", "capsule"])
    func primitives(name: String) throws {
        let mesh: Mesh = switch name {
        case "cube": .cube()
        case "icoSphere": .icoSphere()
        case "sphere": .sphere()
        case "torus": .torus()
        case "cylinder": .cylinder()
        default: .capsule()
        }
        let boolean = try BooleanMesh(mesh: mesh)
        #expect(boolean.isManifold)
        #expect(boolean.numEdge * 2 == boolean.halfedges.count)
        // Euler characteristic of the merged triangle mesh matches the solid's genus.
        let chi = boolean.numVert - boolean.numEdge + boolean.numTri
        #expect(chi == (name == "torus" ? 0 : 2))
        #expect(boolean.halfedges.allSatisfy { $0.sourceCorner >= 0 })
    }

    @Test("Round trip keeps geometry and topology")
    func roundTrip() throws {
        let mesh = Mesh.icoSphere(subdivisions: 2, attributes: [])
        let back = try BooleanMesh(mesh: mesh).toMesh()
        #expect(back.isManifold)
        #expect(back.faceCount == mesh.faceCount)
        #expect(back.vertexCount == mesh.vertexCount)
        #expect(Set(back.positions.map { [$0.x, $0.y, $0.z] }) == Set(mesh.positions.map { [$0.x, $0.y, $0.z] }))
    }

    @Test("Open and non-manifold inputs are rejected")
    func rejected() {
        #expect(throws: BooleanMesh.ConversionError.notManifold) {
            try BooleanMesh(mesh: .quad(attributes: []))
        }
        // Three triangles fanned around one edge.
        let fan = Mesh(positions: [[0, 0, 0], [1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1]], faces: [[0, 1, 2], [1, 0, 3], [0, 1, 4]])
        #expect(throws: BooleanMesh.ConversionError.notManifold) {
            try BooleanMesh(mesh: fan)
        }
    }

    @Test("Normals: outward faces and unit pseudo-normals pointing away from the center")
    func normals() throws {
        let boolean = try BooleanMesh(mesh: .icoSphere(subdivisions: 1, attributes: []))
        for triangle in 0..<boolean.numTri {
            let centroid = (0..<3).reduce(SIMD3<Double>.zero) { $0 + boolean.vertPos[boolean.halfedges[3 * triangle + $1].startVert] } / 3
            #expect(simd_dot(boolean.faceNormal[triangle], centroid) > 0)
        }
        for (index, normal) in boolean.vertNormal.enumerated() {
            #expect(abs(simd_length(normal) - 1) < 1e-12)
            // On a sphere the pseudo-normal is nearly radial.
            #expect(simd_dot(normal, simd_normalize(boolean.vertPos[index])) > 0.99)
        }
    }

    @Test("Epsilon scales with the bounding box at Float precision")
    func epsilon() throws {
        let small = try BooleanMesh(mesh: .cube(extents: [1, 1, 1], attributes: []))
        let large = try BooleanMesh(mesh: .cube(extents: [100, 100, 100], attributes: []))
        #expect(abs(small.scale - 0.5) < 1e-12)
        #expect(abs(small.epsilon - Double(Float.ulpOfOne) * 0.5) < 1e-18)
        #expect(abs(large.epsilon / small.epsilon - 100) < 1e-9)
    }
}
