import simd
@testable import SwiftMesh
import Testing

@Suite("Boolean attributes")
struct BooleanAttributeTests {
    /// Flat normals plus linear fields: UV = (x, y), color = (x, y, z, 1).
    private func decorated(_ mesh: Mesh) -> Mesh {
        var mesh = mesh.withFlatNormals()
        mesh.textureCoordinates = mesh.topology.halfEdges.map { halfEdge in
            let p = mesh.positions[halfEdge.origin.raw]
            return SIMD2(p.x, p.y)
        }
        mesh.colors = mesh.topology.halfEdges.map { halfEdge in
            let p = mesh.positions[halfEdge.origin.raw]
            return SIMD4(p.x, p.y, p.z, 1)
        }
        return mesh
    }

    private func run(_ a: Mesh, _ b: Mesh, _ operation: BooleanOperation, clean: Bool) throws -> Mesh {
        let p = try BooleanMesh(mesh: a)
        let q = try BooleanMesh(mesh: b)
        var result = BooleanAssembler(p, q, operation: operation).assemble().triangulated()
        if clean {
            result = result.removingDegenerates()
        }
        return result.toMesh(attributesFrom: p, q, invertQ: operation == .difference)
    }

    @Test("Linear fields are reproduced exactly; normals match the result's faces", arguments: [
        (BooleanOperation.union, false), (.intersection, false), (.difference, false),
        (.union, true), (.intersection, true), (.difference, true)
    ])
    func linearFields(operation: BooleanOperation, clean: Bool) throws {
        let sphere = decorated(.icoSphere(extents: [0.8, 0.8, 0.8], subdivisions: 2, attributes: []))
        let rotation = simd_float4x4(simd_quatf(angle: 0.6, axis: simd_normalize([1, 2, 3])))
        let cube = decorated(Mesh.cube(extents: [0.5, 0.5, 0.5], attributes: []).transformed(by: rotation).translated(by: [0.2, 0.15, 0.1]))
        let result = try run(sphere, cube, operation, clean: clean)
        let uvs = try #require(result.textureCoordinates)
        let colors = try #require(result.colors)
        let normals = try #require(result.normals)
        #expect(uvs.count == result.topology.halfEdges.count)
        for halfEdge in result.topology.halfEdges {
            let p = result.positions[halfEdge.origin.raw]
            #expect(simd_distance(uvs[halfEdge.id.raw], SIMD2(p.x, p.y)) < 1e-5)
            #expect(simd_distance(colors[halfEdge.id.raw], SIMD4(p.x, p.y, p.z, 1)) < 1e-5)
            // Uncleaned results can hold slivers whose computed normal is noise.
            let corners = result.facePositions(halfEdge.face!)
            let area = simd_length(simd_cross(corners[1] - corners[0], corners[2] - corners[0])) / 2
            if area > 1e-8 {
                #expect(simd_dot(normals[halfEdge.id.raw], result.faceNormal(halfEdge.face!)) > 0.999)
            }
        }
    }

    @Test("Retained faces keep their exact input attributes")
    func retainedFaces() throws {
        var a = Mesh.cube(attributes: [.textureCoordinates])
        a.textureCoordinates = a.topology.halfEdges.map { SIMD2(Float($0.id.raw), 0.5) } // arbitrary per corner
        let b = Mesh.cube(attributes: [.textureCoordinates]).translated(by: [5, 0, 0])
        let result = try run(a, b, .union, clean: true)
        let uvs = try #require(result.textureCoordinates)
        // Every corner from A carries one of A's original values unchanged.
        let originals = Set(a.textureCoordinates!.map { [$0.x, $0.y] })
        let fromA = result.topology.halfEdges.filter { result.positions[$0.origin.raw].x < 2 }
        #expect(!fromA.isEmpty)
        #expect(fromA.allSatisfy { originals.contains([uvs[$0.id.raw].x, uvs[$0.id.raw].y]) })
    }

    @Test("Attributes missing on either input are dropped")
    func missingAttributes() throws {
        let a = Mesh.cube(attributes: [.textureCoordinates])
        let b = Mesh.cube(attributes: []).translated(by: [0.5, 0, 0])
        let result = try run(a, b, .union, clean: true)
        #expect(result.textureCoordinates == nil)
    }

    @Test("Barycentric snaps to vertices and edges within tolerance")
    func barycentricSnapping() {
        let triangle: [SIMD3<Double>] = [[0, 0, 0], [1, 0, 0], [0, 1, 0]]
        #expect(barycentric([1e-12, 0, 0], triangle, tolerance: 1e-9) == SIMD3(1, 0, 0))
        let onEdge = barycentric([0.5, 1e-12, 0], triangle, tolerance: 1e-9)
        #expect(onEdge.z == 0)
        #expect(abs(onEdge.x - 0.5) < 1e-12)
        let inside = barycentric([0.25, 0.25, 0], triangle, tolerance: 1e-9)
        #expect(simd_distance(inside, [0.5, 0.25, 0.25]) < 1e-12)
    }
}
