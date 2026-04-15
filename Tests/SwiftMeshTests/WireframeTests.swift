import simd
@testable import SwiftMesh
import Testing

// MARK: - Mesh.merged tests

@Suite("Mesh merging")
struct MeshMergedTests {
    @Test("Merging empty array returns empty mesh")
    func mergeEmpty() {
        let result = Mesh.merged([])
        #expect(result.vertexCount == 0)
        #expect(result.faceCount == 0)
    }

    @Test("Merging single mesh returns equivalent mesh")
    func mergeSingle() {
        let cube = Mesh.cube()
        let result = Mesh.merged([cube])
        #expect(result.vertexCount == cube.vertexCount)
        #expect(result.faceCount == cube.faceCount)
    }

    @Test("Merging two cubes doubles vertex and face count")
    func mergeTwoCubes() {
        let a = Mesh.cube(attributes: [])
        let b = Mesh.cube(attributes: []).translated(by: SIMD3(3, 0, 0))
        let result = Mesh.merged([a, b])
        #expect(result.vertexCount == a.vertexCount + b.vertexCount)
        #expect(result.faceCount == a.faceCount + b.faceCount)
    }

    @Test("Merged mesh preserves normals when all inputs have them")
    func mergePreservesNormals() {
        let a = Mesh.cube(attributes: [.flatNormals])
        let b = Mesh.cube(attributes: [.flatNormals])
        let result = Mesh.merged([a, b])
        #expect(result.normals != nil)
    }

    @Test("Merged mesh drops normals when any input lacks them")
    func mergeDropsNormals() {
        let a = Mesh.cube(attributes: [.flatNormals])
        let b = Mesh.cube(attributes: [])
        let result = Mesh.merged([a, b])
        #expect(result.normals == nil)
    }

    @Test("Merged mesh validates cleanly")
    func mergeValidates() {
        let a = Mesh.cube(attributes: [])
        let b = Mesh.tetrahedron(attributes: [])
        let result = Mesh.merged([a, b])
        let issues = result.validate().filter { $0.severity == .error }
        #expect(issues.isEmpty)
    }
}

// MARK: - edgePrism tests

@Suite("Edge prism generation")
struct EdgePrismTests {
    @Test("Prism along X axis has correct vertex count")
    func prismVertexCount() {
        let sides = 6
        let prism = Mesh.edgePrism(
            from: SIMD3(0, 0, 0),
            to: SIMD3(1, 0, 0),
            radius: 0.1,
            sides: sides,
            capped: true
        )
        // 2 rings × sides vertices
        #expect(prism.vertexCount == 2 * sides)
        // sides quads + 2 caps
        #expect(prism.faceCount == sides + 2)
    }

    @Test("Uncapped prism has no cap faces")
    func uncappedPrism() {
        let sides = 4
        let prism = Mesh.edgePrism(
            from: SIMD3(0, 0, 0),
            to: SIMD3(0, 1, 0),
            radius: 0.05,
            sides: sides,
            capped: false
        )
        #expect(prism.faceCount == sides)
    }

    @Test("Degenerate edge returns empty mesh")
    func degenerateEdge() {
        let prism = Mesh.edgePrism(
            from: SIMD3(1, 2, 3),
            to: SIMD3(1, 2, 3),
            radius: 0.1,
            sides: 4
        )
        #expect(prism.vertexCount == 0)
        #expect(prism.faceCount == 0)
    }

    @Test("Prism validates cleanly")
    func prismValidates() {
        let prism = Mesh.edgePrism(
            from: SIMD3(-1, 0, 0),
            to: SIMD3(1, 0, 0),
            radius: 0.1,
            sides: 8
        )
        let issues = prism.validate().filter { $0.severity == .error }
        #expect(issues.isEmpty)
    }

    @Test("Prism radius matches expected bounds")
    func prismRadius() {
        let radius: Float = 0.2
        let prism = Mesh.edgePrism(
            from: SIMD3(0, 0, 0),
            to: SIMD3(0, 0, 1),
            radius: radius,
            sides: 32
        )
        // All vertices should be within radius of the Z axis
        for pos in prism.positions {
            let distFromAxis = sqrt(pos.x * pos.x + pos.y * pos.y)
            #expect(distFromAxis <= radius + 1e-5)
            #expect(distFromAxis >= radius - 1e-5)
        }
    }
}

// MARK: - Wireframe tests

@Suite("Wireframe mesh generation")
struct WireframeTests {
    @Test("Cube wireframe has 12 edges worth of prisms")
    func cubeWireframe() {
        let cube = Mesh.cube(attributes: [])
        let wireframe = cube.wireframe(radius: 0.02, sides: 4, attributes: [])
        // Cube has 12 edges, each prism: 8 verts, 6 faces (4 sides + 2 caps)
        #expect(wireframe.vertexCount == 12 * 8)
        #expect(wireframe.faceCount == 12 * 6)
    }

    @Test("Tetrahedron wireframe has 6 edges worth of prisms")
    func tetrahedronWireframe() {
        let tet = Mesh.tetrahedron(attributes: [])
        let wireframe = tet.wireframe(radius: 0.01, sides: 3, attributes: [])
        // Tetrahedron has 6 edges, each prism: 6 verts, 5 faces (3 sides + 2 caps)
        #expect(wireframe.vertexCount == 6 * 6)
        #expect(wireframe.faceCount == 6 * 5)
    }

    @Test("Wireframe validates cleanly")
    func wireframeValidates() {
        let cube = Mesh.cube(attributes: [])
        let wireframe = cube.wireframe(radius: 0.05, sides: 6, attributes: [])
        let issues = wireframe.validate().filter { $0.severity == .error }
        #expect(issues.isEmpty)
    }

    @Test("Wireframe with attributes generates normals")
    func wireframeWithNormals() {
        let cube = Mesh.cube(attributes: [])
        let wireframe = cube.wireframe(radius: 0.02, sides: 4, attributes: [.flatNormals])
        #expect(wireframe.normals != nil)
    }

    @Test("Cylindrical wireframe (high sides) validates")
    func cylindricalWireframe() {
        let cube = Mesh.cube(attributes: [])
        let wireframe = cube.wireframe(radius: 0.03, sides: 16, attributes: [])
        let issues = wireframe.validate().filter { $0.severity == .error }
        #expect(issues.isEmpty)
    }

    @Test("Uncapped wireframe has fewer faces")
    func uncappedWireframe() {
        let cube = Mesh.cube(attributes: [])
        let capped = cube.wireframe(radius: 0.02, sides: 4, capped: true, attributes: [])
        let uncapped = cube.wireframe(radius: 0.02, sides: 4, capped: false, attributes: [])
        // Each edge loses 2 cap faces
        #expect(uncapped.faceCount == capped.faceCount - 12 * 2)
    }

    @Test("Sides clamped to minimum of 3")
    func sidesClampedToMinimum() {
        let cube = Mesh.cube(attributes: [])
        let wireframe = cube.wireframe(radius: 0.02, sides: 1, attributes: [])
        // Should use 3 sides minimum: 12 edges × (3 + 2) = 60
        #expect(wireframe.faceCount == 12 * 5)
    }
}
