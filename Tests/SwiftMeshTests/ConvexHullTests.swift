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

    @Test("Large point cloud hull is closed and contains every point")
    func largePointCloud() throws {
        var points: [SIMD3<Float>] = []
        var seed: UInt32 = 7
        func next() -> Float {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Float(seed % 10_000) / 5_000 - 1
        }
        for _ in 0..<5_000 {
            points.append(SIMD3(next(), next(), next()))
        }
        let mesh = try #require(Mesh.convexHull(of: points, attributes: []))
        #expect(mesh.validate().isEmpty)
        #expect(mesh.isManifold)
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount == 2)
        let planes = mesh.topology.faces.map { (normal: mesh.faceNormal($0.id), point: mesh.faceCentroid($0.id)) }
        let outside = points.filter { point in planes.contains { simd_dot($0.normal, point - $0.point) > 1e-4 } }
        #expect(outside.isEmpty)
    }

    @Test("Hull of spheres: single sphere, capsule-like pair, and mixed radii")
    func spheres() throws {
        let single = try #require(Mesh.convexHull(ofSpheres: [([1, 2, 3], 0.5)], attributes: []))
        #expect(single.isManifold)
        #expect(single.positions.allSatisfy { abs(simd_distance($0, [1, 2, 3]) - 0.5) < 1e-5 })

        // Two equal spheres: a capsule along x of length 2 + 2r.
        let pair = try #require(Mesh.convexHull(ofSpheres: [([-1, 0, 0], 0.5), ([1, 0, 0], 0.5)], subdivisions: 3, attributes: []))
        #expect(pair.isManifold)
        #expect(abs(pair.bounds!.max.x - 1.5) < 1e-5)
        #expect(abs(pair.bounds!.min.x + 1.5) < 1e-5)
        #expect(pair.bounds!.max.y <= 0.5 + 1e-5)
        #expect(pair.bounds!.max.y > 0.48)

        // Mixed radii: every vertex lies on one of the spheres, and the big sphere dominates its side.
        let spheres: [(center: SIMD3<Float>, radius: Float)] = [([0, 0, 0], 1), ([3, 0, 0], 0.25), ([0, 3, 0], 0)]
        let mixed = try #require(Mesh.convexHull(ofSpheres: spheres, attributes: []))
        #expect(mixed.isManifold)
        #expect(mixed.positions.allSatisfy { position in spheres.contains { abs(simd_distance(position, $0.center) - $0.radius) < 1e-5 } })
        #expect(abs(mixed.bounds!.min.x + 1) < 1e-5)
        #expect(abs(mixed.bounds!.max.x - 3.25) < 1e-5)
        #expect(abs(mixed.bounds!.max.y - 3) < 1e-5)
    }

    @Test("Hull of zero-radius coplanar spheres is degenerate")
    func degenerateSpheres() {
        #expect(Mesh.convexHull(ofSpheres: [([0, 0, 0], 0), ([1, 0, 0], 0), ([0, 1, 0], 0), ([1, 1, 0], 0)]) == nil)
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
