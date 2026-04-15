import simd
@testable import SwiftMesh
import Testing

@Suite("Convex Hull")
struct ConvexHullTests {
    // MARK: - Degenerate inputs

    @Test("Too few points returns nil")
    func tooFewPoints() {
        #expect(Mesh.convexHull(of: [], attributes: []) == nil)
        #expect(Mesh.convexHull(of: [SIMD3(0, 0, 0)], attributes: []) == nil)
        #expect(Mesh.convexHull(of: [SIMD3(0, 0, 0), SIMD3(1, 0, 0)], attributes: []) == nil)
        #expect(Mesh.convexHull(of: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(2, 0, 0)], attributes: []) == nil)
    }

    @Test("Coplanar points returns nil")
    func coplanarPoints() {
        let points: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(1, 1, 0)
        ]
        #expect(Mesh.convexHull(of: points, attributes: []) == nil)
    }

    @Test("Collinear points returns nil")
    func collinearPoints() {
        let points: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(2, 0, 0), SIMD3(3, 0, 0)
        ]
        #expect(Mesh.convexHull(of: points, attributes: []) == nil)
    }

    @Test("Coincident points returns nil")
    func coincidentPoints() {
        let points = [SIMD3<Float>](repeating: SIMD3(1, 2, 3), count: 10)
        #expect(Mesh.convexHull(of: points, attributes: []) == nil)
    }

    // MARK: - Simple hulls

    @Test("Tetrahedron from 4 points")
    func tetrahedron() throws {
        let points: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)
        ]
        let mesh = try #require(Mesh.convexHull(of: points, attributes: []))
        #expect(mesh.vertexCount == 4)
        #expect(mesh.faceCount == 4)
        #expect(mesh.validate().isEmpty)
        // Euler: V - E + F = 2
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("Cube hull from 8 corners")
    func cubeCorners() throws {
        let points: [SIMD3<Float>] = [
            SIMD3(-1, -1, -1), SIMD3(1, -1, -1), SIMD3(1, 1, -1), SIMD3(-1, 1, -1),
            SIMD3(-1, -1, 1), SIMD3(1, -1, 1), SIMD3(1, 1, 1), SIMD3(-1, 1, 1)
        ]
        let mesh = try #require(Mesh.convexHull(of: points, attributes: []))
        #expect(mesh.vertexCount == 8)
        // A cube triangulated has 12 triangular faces
        #expect(mesh.faceCount == 12)
        #expect(mesh.validate().isEmpty)
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("Interior points are excluded")
    func interiorPointsExcluded() throws {
        // Cube corners + interior points
        var points: [SIMD3<Float>] = [
            SIMD3(-1, -1, -1), SIMD3(1, -1, -1), SIMD3(1, 1, -1), SIMD3(-1, 1, -1),
            SIMD3(-1, -1, 1), SIMD3(1, -1, 1), SIMD3(1, 1, 1), SIMD3(-1, 1, 1)
        ]
        // Add interior points
        points.append(SIMD3(0, 0, 0))
        points.append(SIMD3(0.5, 0.5, 0.5))
        points.append(SIMD3(-0.3, 0.2, 0.1))

        let mesh = try #require(Mesh.convexHull(of: points, attributes: []))
        #expect(mesh.vertexCount == 8) // only cube corners on hull
        #expect(mesh.faceCount == 12)
        #expect(mesh.validate().isEmpty)
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
    }

    @Test("Hull is closed manifold")
    func closedManifold() throws {
        let points: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1),
            SIMD3(1, 1, 0), SIMD3(1, 0, 1), SIMD3(0, 1, 1), SIMD3(1, 1, 1)
        ]
        let mesh = try #require(Mesh.convexHull(of: points, attributes: []))
        #expect(mesh.isManifold)
        #expect(mesh.validate().isEmpty)
    }

    @Test("Outward-facing normals")
    func outwardNormals() throws {
        let points: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)
        ]
        let mesh = try #require(Mesh.convexHull(of: points, attributes: []))
        let center = mesh.center

        // Every face normal should point away from the center
        for face in mesh.topology.faces {
            let normal = mesh.faceNormal(face.id)
            let centroid = mesh.faceCentroid(face.id)
            let outward = centroid - center
            #expect(simd_dot(normal, outward) > 0, "Face \(face.id.raw) normal points inward")
        }
    }

    // MARK: - Random point clouds

    @Test("Random point cloud produces valid hull")
    func randomPointCloud() throws {
        // Use a simple deterministic "random" sequence
        var points: [SIMD3<Float>] = []
        var seed: UInt32 = 42
        for _ in 0..<50 {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let x = Float(seed % 1_000) / 500.0 - 1.0
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let y = Float(seed % 1_000) / 500.0 - 1.0
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let z = Float(seed % 1_000) / 500.0 - 1.0
            points.append(SIMD3(x, y, z))
        }

        let mesh = try #require(Mesh.convexHull(of: points, attributes: []))
        #expect(mesh.validate().isEmpty)
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
        #expect(mesh.isManifold)

        // All input points should be inside or on the hull
        let center = mesh.center
        for face in mesh.topology.faces {
            let normal = mesh.faceNormal(face.id)
            let centroid = mesh.faceCentroid(face.id)
            let outward = centroid - center
            #expect(simd_dot(normal, outward) > 0)
        }
    }

    @Test("Points on a sphere produce valid hull")
    func spherePoints() throws {
        var points: [SIMD3<Float>] = []
        // Golden spiral distribution
        let n = 30
        let goldenRatio: Float = (1 + sqrt(5)) / 2
        for i in 0..<n {
            let theta = acos(1 - 2 * (Float(i) + 0.5) / Float(n))
            let phi = 2 * Float.pi * Float(i) / goldenRatio
            points.append(SIMD3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta)))
        }

        let mesh = try #require(Mesh.convexHull(of: points, attributes: []))
        #expect(mesh.validate().isEmpty)
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
        #expect(mesh.isManifold)
    }

    // MARK: - Attributes

    @Test("Hull with default attributes has normals")
    func hullWithAttributes() throws {
        let points: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)
        ]
        let mesh = try #require(Mesh.convexHull(of: points, attributes: .flatNormals))
        #expect(mesh.normals != nil)
        #expect(mesh.validate().isEmpty)
    }

    // MARK: - Convexity

    @Test("All input points are inside or on the hull")
    func allPointsContained() throws {
        let points: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(2, 0, 0), SIMD3(0, 2, 0), SIMD3(0, 0, 2),
            SIMD3(1, 1, 0), SIMD3(1, 0, 1), SIMD3(0, 1, 1),
            SIMD3(0.5, 0.5, 0.5), SIMD3(0.1, 0.1, 0.1)
        ]
        let mesh = try #require(Mesh.convexHull(of: points, attributes: []))

        // For each face, all points should be on or behind the face plane
        for face in mesh.topology.faces {
            let facePositions = mesh.facePositions(face.id)
            let a = facePositions[0]
            let normal = mesh.faceNormal(face.id)

            for p in points {
                let d = simd_dot(normal, p - a)
                #expect(d < 1e-4, "Point \(p) is in front of face \(face.id.raw) by \(d)")
            }
        }
    }

    // MARK: - Duplicate points

    @Test("Duplicate points are handled correctly")
    func duplicatePoints() throws {
        let points: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(0, 0, 0), SIMD3(0, 0, 0),
            SIMD3(1, 0, 0), SIMD3(1, 0, 0),
            SIMD3(0, 1, 0),
            SIMD3(0, 0, 1)
        ]
        let mesh = try #require(Mesh.convexHull(of: points, attributes: []))
        #expect(mesh.vertexCount == 4)
        #expect(mesh.faceCount == 4)
        #expect(mesh.validate().isEmpty)
    }
}
