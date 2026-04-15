import simd
@testable import SwiftMesh
import Testing

@Suite("Marching Cubes")
struct MarchingCubesTests {
    // MARK: - TriangleSoup

    @Test("Sphere SDF produces non-empty soup")
    func sphereSDF() {
        let soup = TriangleSoup.marchingCubes(resolution: 16) { p in
            simd_length(p) - 0.4
        }
        #expect(soup.triangleCount > 0)
        #expect(soup.positionCount > 0)
    }

    @Test("Entirely outside field produces empty soup")
    func entirelyOutside() {
        let soup = TriangleSoup.marchingCubes(resolution: 8) { _ in
            1.0 // all positive = outside
        }
        #expect(soup.triangleCount == 0)
    }

    @Test("Entirely inside field produces empty soup")
    func entirelyInside() {
        let soup = TriangleSoup.marchingCubes(resolution: 8) { _ in
            -1.0 // all negative = inside
        }
        #expect(soup.triangleCount == 0)
    }

    @Test("Higher resolution produces more triangles")
    func resolutionScaling() {
        let field: (SIMD3<Float>) -> Float = { p in simd_length(p) - 0.3 }
        let lowRes = TriangleSoup.marchingCubes(resolution: 8, field: field)
        let highRes = TriangleSoup.marchingCubes(resolution: 16, field: field)
        #expect(highRes.triangleCount > lowRes.triangleCount)
    }

    @Test("Per-axis resolution works")
    func perAxisResolution() {
        let soup = TriangleSoup.marchingCubes(
            resolution: SIMD3(8, 16, 8)
        ) { p in
            simd_length(p) - 0.3
        }
        #expect(soup.triangleCount > 0)
    }

    @Test("Custom bounds work")
    func customBounds() {
        // Sphere of radius 2 centered at origin, sampled in [-3, 3]
        let soup = TriangleSoup.marchingCubes(
            resolution: 16,
            bounds: (SIMD3(-3, -3, -3), SIMD3(3, 3, 3))
        ) { p in
            simd_length(p) - 2.0
        }
        #expect(soup.triangleCount > 0)

        // All positions should be roughly on the sphere surface
        for pos in soup.positions {
            let dist = abs(simd_length(pos) - 2.0)
            #expect(dist < 0.5, "Position \(pos) too far from sphere surface")
        }
    }

    @Test("Custom iso value works")
    func customIsoValue() {
        // Use isoValue=0.5 with a sphere SDF => isosurface at distance 0.5 from origin
        let soup = TriangleSoup.marchingCubes(
            resolution: 16,
            isoValue: 0.2
        ) { p in
            simd_length(p) - 0.4
        }
        #expect(soup.triangleCount > 0)
    }

    // MARK: - Mesh

    @Test("Mesh marchingCubes produces valid mesh")
    func meshMarchingCubes() {
        let mesh = Mesh.marchingCubes(resolution: 16) { p in
            simd_length(p) - 0.3
        }
        #expect(mesh.faceCount > 0)
        #expect(mesh.vertexCount > 0)
        let issues = mesh.validate()
        #expect(issues.isEmpty, "Mesh validation issues: \(issues)")
    }

    @Test("Mesh marchingCubes with smooth normals")
    func meshWithSmoothNormals() {
        let mesh = Mesh.marchingCubes(
            resolution: 12,
            attributes: [.smoothNormals]
        ) { p in
            simd_length(p) - 0.3
        }
        #expect(mesh.normals != nil)
        #expect(mesh.faceCount > 0)
    }

    @Test("Box SDF produces mesh")
    func boxSDF() {
        // Rounded box SDF
        let mesh = Mesh.marchingCubes(resolution: 16) { p in
            let q = SIMD3<Float>(abs(p.x), abs(p.y), abs(p.z)) - SIMD3<Float>(0.25, 0.25, 0.25)
            let outside = simd_length(max(q, SIMD3<Float>.zero))
            let inside = min(max(q.x, max(q.y, q.z)), Float(0))
            return outside + inside
        }
        #expect(mesh.faceCount > 0)
    }

    @Test("Torus SDF produces mesh")
    func torusSDF() {
        let mesh = Mesh.marchingCubes(resolution: 24) { p in
            let q = SIMD2<Float>(simd_length(SIMD2<Float>(p.x, p.z)) - 0.25, p.y)
            return simd_length(q) - 0.1
        }
        #expect(mesh.faceCount > 0)
    }
}
