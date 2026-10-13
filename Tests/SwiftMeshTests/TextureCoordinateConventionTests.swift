import simd
@testable import SwiftMesh
import Testing

// Generated texture coordinates follow glTF and Metal: (0, 0) is the top-left of the image and v runs down, and a
// texture seen from outside a front face is not mirrored.
@Suite("Texture coordinate convention")
struct TextureCoordinateConventionTests {
    struct Measurement {
        // Front faces are counter-clockwise; with v down, an unmirrored UV triangle is clockwise (negative area).
        var mirroredTriangles = 0
        var unmirroredTriangles = 0
        // On faces that look sideways, which way +v runs in 3D.
        var sideVUp = 0
        var sideVDown = 0
        // On faces that look sideways, +v runs mostly horizontally: the texture is turned on its side.
        var sideVSideways = 0
    }

    static func measure(_ mesh: Mesh) -> Measurement {
        var measurement = Measurement()
        guard let uvs = mesh.textureCoordinates else {
            return measurement
        }
        let topology = mesh.topology
        for face in topology.faces {
            for (a, b, c) in mesh.triangulatedCorners(of: face.id) {
                let p0 = mesh.positions[topology.halfEdges[a.raw].origin.raw]
                let edge1 = mesh.positions[topology.halfEdges[b.raw].origin.raw] - p0
                let edge2 = mesh.positions[topology.halfEdges[c.raw].origin.raw] - p0
                let delta1 = uvs[b.raw] - uvs[a.raw]
                let delta2 = uvs[c.raw] - uvs[a.raw]
                let area = delta1.x * delta2.y - delta2.x * delta1.y
                if area < -1e-9 {
                    measurement.unmirroredTriangles += 1
                } else if area > 1e-9 {
                    measurement.mirroredTriangles += 1
                } else {
                    continue
                }
                guard abs(simd_normalize(simd_cross(edge1, edge2)).y) < 0.7 else {
                    continue
                }
                let positionPerV = (edge2 * delta1.x - edge1 * delta2.x) / area
                if abs(simd_normalize(positionPerV).y) < 0.5 {
                    measurement.sideVSideways += 1
                } else if positionPerV.y > 0 {
                    measurement.sideVUp += 1
                } else {
                    measurement.sideVDown += 1
                }
            }
        }
        return measurement
    }

    static let attributes: MeshAttributes = [.flatNormals, .textureCoordinates]

    // Shapes with an up direction: textures on their sides are upright.
    static let uprightShapes: [(String, Mesh)] = [
        ("cube", .cube(attributes: attributes)),
        ("quad", .quad(attributes: attributes)),
        ("triangle", .triangle(attributes: attributes)),
        ("box", .box(attributes: attributes)),
        ("circle", .circle(attributes: attributes)),
        ("sphere", .sphere(attributes: attributes)),
        ("icoSphere", .icoSphere(attributes: attributes)),
        ("cubeSphere", .cubeSphere(attributes: attributes)),
        ("cylinder", .cylinder(attributes: attributes)),
        ("hemisphere", .hemisphere(attributes: attributes)),
        ("capsule", .capsule(attributes: attributes)),
        ("cone", .cone(attributes: attributes)),
        ("conicalFrustum", .conicalFrustum(attributes: attributes)),
        ("rectangularFrustum", .rectangularFrustum(attributes: attributes)),
        ("teapot", .teapot(attributes: attributes)),
        ("cylindricalUVs", Mesh.cylinder(attributes: [.flatNormals]).withCylindricalUVs()),
        ("boxUVs", Mesh.box(attributes: [.flatNormals]).withBoxUVs())
    ]

    // Exact axis permutations (no rounding), so cap vertices stay coplanar.
    static let yToX = simd_float4x4(columns: ([0, 0, 1, 0], [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 0, 1]))
    static let yToZ = simd_float4x4(columns: ([0, 1, 0, 0], [0, 0, 1, 0], [1, 0, 0, 0], [0, 0, 0, 1]))

    // Faces of these have no common up direction (polyhedron faces, the torus tube).
    static let unorientedShapes: [(String, Mesh)] = [
        ("tetrahedron", .tetrahedron(attributes: attributes)),
        ("octahedron", .octahedron(attributes: attributes)),
        ("icosahedron", .icosahedron(attributes: attributes)),
        ("dodecahedron", .dodecahedron(attributes: attributes)),
        ("torus", .torus(attributes: attributes)),
        ("boxUVs sphere", Mesh.sphere(attributes: [.flatNormals]).withBoxUVs()),
        ("cylindricalUVs x", Mesh.cylinder(attributes: [.flatNormals]).transformed(by: yToX).withCylindricalUVs(axis: .x)),
        ("cylindricalUVs z", Mesh.cylinder(attributes: [.flatNormals]).transformed(by: yToZ).withCylindricalUVs(axis: .z))
    ]

    @Test("Planar UVs are not mirrored seen from the positive end of the axis", arguments: [ProjectionAxis.x, .y, .z])
    func planarNotMirrored(_ axis: ProjectionAxis) {
        let normal: SIMD3<Float> = switch axis {
        case .x: [1, 0, 0]
        case .y: [0, 1, 0]
        case .z: [0, 0, 1]
        }
        // A quad faces +Z; turn it to face the axis.
        let quad = Mesh.quad(attributes: [])
        let turned = normal.z == 1 ? quad : quad.rotated(by: simd_quatf(from: [0, 0, 1], to: normal))
        let measurement = Self.measure(turned.withPlanarUVs(axis: axis))
        #expect(measurement.unmirroredTriangles > 0)
        #expect(measurement.mirroredTriangles == 0)
        if axis != .y {
            #expect(measurement.sideVUp == 0 && measurement.sideVSideways == 0)
        }
    }

    @Test("Textures are not mirrored", arguments: uprightShapes + unorientedShapes)
    func notMirrored(_ name: String, _ mesh: Mesh) {
        let measurement = Self.measure(mesh)
        #expect(measurement.unmirroredTriangles > 0, "\(name) has no UVs")
        #expect(measurement.mirroredTriangles == 0, "\(name): \(measurement.mirroredTriangles) mirrored triangles")
    }

    @Test("v runs down the sides", arguments: uprightShapes)
    func vRunsDown(_ name: String, _ mesh: Mesh) {
        let measurement = Self.measure(mesh)
        #expect(measurement.sideVUp == 0, "\(name): +v runs up on \(measurement.sideVUp) side triangles")
        #expect(measurement.sideVSideways == 0, "\(name): +v runs sideways on \(measurement.sideVSideways) side triangles")
    }
}
