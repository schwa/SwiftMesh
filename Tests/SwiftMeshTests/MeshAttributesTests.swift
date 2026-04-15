import simd
@testable import SwiftMesh
import Testing

@Suite("Mesh Attributes")
struct MeshAttributesTests {
    // MARK: - Flat Normals

    @Test("withFlatNormals on XY plane triangle")
    func flatNormalsTriangle() {
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)
        ], faces: [[0, 1, 2]]).withFlatNormals()

        #expect(mesh.normals != nil)
        #expect(mesh.normals!.count == mesh.topology.halfEdges.count)
        // All corners should have the same normal (face normal)
        for normal in mesh.normals! {
            #expect(abs(normal.z) > 0.9)
        }
        #expect(mesh.validate() == nil)
    }

    @Test("withFlatNormals on cube gives 6 distinct normals")
    func flatNormalsCube() {
        let mesh = Mesh.cube(attributes: []).withFlatNormals()
        #expect(mesh.normals != nil)

        // Collect unique normals (quantized to avoid float noise)
        var uniqueNormals = Set<String>()
        for normal in mesh.normals! {
            let key = "\(Int(round(normal.x * 10))),\(Int(round(normal.y * 10))),\(Int(round(normal.z * 10)))"
            uniqueNormals.insert(key)
        }
        #expect(uniqueNormals.count == 6)
    }

    // MARK: - Smooth Normals

    @Test("withSmoothNormals on sphere-like mesh")
    func smoothNormalsSphere() {
        let mesh = Mesh.icosahedron(attributes: []).withSmoothNormals()
        #expect(mesh.normals != nil)
        #expect(mesh.normals!.count == mesh.topology.halfEdges.count)

        // For a normalized icosahedron, smooth normals should roughly equal positions
        for he in mesh.topology.halfEdges {
            let pos = mesh.positions[he.origin.raw]
            let normal = mesh.normals![he.id.raw]
            let dot = simd_dot(simd_normalize(pos), normal)
            #expect(dot > 0.9, "Smooth normal should roughly align with position direction on icosahedron")
        }
    }

    @Test("withSmoothNormals produces unit-length normals")
    func smoothNormalsUnitLength() {
        let mesh = Mesh.cube(attributes: []).withSmoothNormals()
        for normal in mesh.normals! {
            let len = simd_length(normal)
            #expect(abs(len - 1.0) < 1e-5)
        }
    }

    // MARK: - Spherical UVs

    @Test("withSphericalUVs produces valid UV range")
    func sphericalUVsRange() {
        let mesh = Mesh.icosahedron(attributes: []).withSphericalUVs()
        #expect(mesh.textureCoordinates != nil)
        #expect(mesh.textureCoordinates!.count == mesh.topology.halfEdges.count)

        for uv in mesh.textureCoordinates! {
            #expect(uv.x >= 0 && uv.x <= 1, "U should be in [0,1], got \(uv.x)")
            #expect(uv.y >= 0 && uv.y <= 1, "V should be in [0,1], got \(uv.y)")
        }
    }

    // MARK: - Tangents

    @Test("withTangents requires normals and UVs")
    func tangentsPipeline() {
        let mesh = Mesh.icosahedron(attributes: [])
            .withSmoothNormals()
            .withSphericalUVs()
            .withTangents()

        #expect(mesh.tangents != nil)
        #expect(mesh.bitangents != nil)
        #expect(mesh.tangents!.count == mesh.topology.halfEdges.count)
        #expect(mesh.bitangents!.count == mesh.topology.halfEdges.count)
        #expect(mesh.validate() == nil)
    }

    @Test("Tangents are roughly unit length")
    func tangentsUnitLength() {
        let mesh = Mesh.octahedron(attributes: [])
            .withFlatNormals()
            .withSphericalUVs()
            .withTangents()

        for tangent in mesh.tangents! {
            let len = simd_length(tangent)
            if len > 0.01 { // skip degenerate corners
                #expect(abs(len - 1.0) < 0.1, "Tangent length should be ~1, got \(len)")
            }
        }
    }

    // MARK: - Chaining

    @Test("Full attribute pipeline validates")
    func fullPipeline() {
        let mesh = Mesh.sphere(latitudeSegments: 8, longitudeSegments: 16)
            .withSmoothNormals()
            .withSphericalUVs()
            .withTangents()

        #expect(mesh.normals != nil)
        #expect(mesh.textureCoordinates != nil)
        #expect(mesh.tangents != nil)
        #expect(mesh.bitangents != nil)
        #expect(mesh.validate() == nil)
    }
}
