import simd
@testable import SwiftMesh
import Testing

@Suite("CSG")
struct CSGTests {
    // MARK: - Helpers

    /// Two unit cubes: one at origin, one shifted by 0.5 along X (overlapping).
    private func overlappingCubes() -> (Mesh, Mesh) {
        let a = Mesh.box(extents: [1, 1, 1], attributes: [])
        // Shift b by 0.5 along X
        var bPositions = Mesh.box(extents: [1, 1, 1], attributes: []).positions
        for i in bPositions.indices {
            bPositions[i].x += 0.5
        }
        let b = Mesh(positions: bPositions, faces: [
            [0, 1, 2, 3], [5, 4, 7, 6],
            [4, 0, 3, 7], [1, 5, 6, 2],
            [3, 2, 6, 7], [4, 5, 1, 0]
        ])
        return (a, b)
    }

    @Test("CSG does not split faces the other solid doesn't touch", arguments: [CSGOperation.union, .difference])
    func noSplitOfUntouchedFaces(operation: CSGOperation) {
        let rotation = simd_quatf(angle: 0.5, axis: simd_normalize([1, 1, 0]))
        var cube = TriangleSoup(mesh: Mesh.box(extents: [2, 2, 2], attributes: []))
        cube.positions = cube.positions.map { rotation.act($0) }
        let sphere = TriangleSoup(mesh: Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 2, attributes: []))
        let result = cube.csg(operation, sphere)
        let onCubeSurface = result.triangles.filter { tri in
            [tri.0, tri.1, tri.2].allSatisfy { simd_reduce_max(simd_abs(rotation.inverse.act(result.positions[$0]))) > 0.999 }
        }
        #expect(onCubeSurface.count == cube.triangles.count)
    }

    // Float BSP internals drift ~8.6e-8 off the input planes here; Double leaves only output rounding (~1.7e-8).
    @Test("CSG output vertices stay on input surfaces")
    func outputVerticesOnInputPlanes() {
        let rotation = simd_quatf(angle: 0.7, axis: simd_normalize([1, 2, 3]))
        let a = TriangleSoup(mesh: Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 3, attributes: []))
        var b = TriangleSoup(mesh: Mesh.box(extents: [0.7, 0.7, 0.7], attributes: []))
        b.positions = b.positions.map { rotation.act($0) + [0.1, 0.05, 0.02] }
        let result = a.intersection(b)
        var planes: [(normal: SIMD3<Double>, w: Double)] = []
        for soup in [a, b] {
            for triangle in soup.triangles {
                let p0 = SIMD3<Double>(soup.positions[triangle.0])
                let p1 = SIMD3<Double>(soup.positions[triangle.1])
                let p2 = SIMD3<Double>(soup.positions[triangle.2])
                let normal = simd_normalize(simd_cross(p1 - p0, p2 - p0))
                planes.append((normal, simd_dot(normal, p0)))
            }
        }
        let worst = result.positions.map { position in
            let point = SIMD3<Double>(position)
            return planes.map { abs(simd_dot($0.normal, point) - $0.w) }.min()!
        }.max()!
        #expect(worst < 4e-8)
    }

    @Test("Convenience CSG methods match csg(_:_:options:)")
    func optionsPathMatchesConvenience() {
        // Vertex/face order can differ between runs, so compare order-independent summaries.
        func summary(_ mesh: Mesh) -> (Int, Int, [[Float]]) {
            (mesh.faceCount, mesh.vertexCount, mesh.positions.map { [$0.x, $0.y, $0.z] }.sorted { $0.lexicographicallyPrecedes($1) })
        }
        let (a, b) = overlappingCubes()
        #expect(summary(a.union(b)) == summary(a.csg(.union, b)))
        #expect(summary(a.intersection(b, mergeCoplanar: false)) == summary(a.csg(.intersection, b, options: .init(mergeCoplanar: false))))
        #expect(summary(a.difference(b, weldTolerance: 1e-3)) == summary(a.csg(.difference, b, options: .init(weldTolerance: 1e-3))))
    }

    @Test("CSGOptions.attributes derives attributes on the result")
    func optionsAttributes() throws {
        let (a, b) = overlappingCubes()
        let plain = a.csg(.union, b)
        let withNormals = a.csg(.union, b, options: .init(attributes: [.flatNormals]))
        #expect(plain.normals == nil)
        let normals = try #require(withNormals.normals)
        #expect(normals.count == withNormals.topology.halfEdges.count)
    }

    /// Two identical unit cubes at origin.
    private func identicalCubes() -> (Mesh, Mesh) {
        let a = Mesh.box(extents: [1, 1, 1], attributes: [])
        let b = Mesh.box(extents: [1, 1, 1], attributes: [])
        return (a, b)
    }

    /// Two non-overlapping unit cubes.
    private func separatedCubes() -> (Mesh, Mesh) {
        let a = Mesh.box(extents: [1, 1, 1], attributes: [])
        var bPositions = Mesh.box(extents: [1, 1, 1], attributes: []).positions
        for i in bPositions.indices {
            bPositions[i].x += 5.0
        }
        let b = Mesh(positions: bPositions, faces: [
            [0, 1, 2, 3], [5, 4, 7, 6],
            [4, 0, 3, 7], [1, 5, 6, 2],
            [3, 2, 6, 7], [4, 5, 1, 0]
        ])
        return (a, b)
    }

    // MARK: - TriangleSoup CSG

    @Test("Union of overlapping cubes produces valid soup")
    func unionOverlapping() {
        let (a, b) = overlappingCubes()
        let soupA = TriangleSoup(mesh: a)
        let soupB = TriangleSoup(mesh: b)
        let result = soupA.union(soupB)
        #expect(result.triangleCount > 0)
    }

    @Test("Intersection of overlapping cubes produces valid soup")
    func intersectionOverlapping() {
        let (a, b) = overlappingCubes()
        let soupA = TriangleSoup(mesh: a)
        let soupB = TriangleSoup(mesh: b)
        let result = soupA.intersection(soupB)
        #expect(result.triangleCount > 0)
    }

    @Test("Difference of overlapping cubes produces valid soup")
    func differenceOverlapping() {
        let (a, b) = overlappingCubes()
        let soupA = TriangleSoup(mesh: a)
        let soupB = TriangleSoup(mesh: b)
        let result = soupA.difference(soupB)
        #expect(result.triangleCount > 0)
    }

    @Test("Union of separated cubes preserves all triangles")
    func unionSeparated() {
        let (a, b) = separatedCubes()
        let soupA = TriangleSoup(mesh: a)
        let soupB = TriangleSoup(mesh: b)
        let result = soupA.union(soupB)
        // Should have all triangles from both meshes
        #expect(result.triangleCount == soupA.triangleCount + soupB.triangleCount)
    }

    @Test("Intersection of separated cubes is empty")
    func intersectionSeparated() {
        let (a, b) = separatedCubes()
        let soupA = TriangleSoup(mesh: a)
        let soupB = TriangleSoup(mesh: b)
        let result = soupA.intersection(soupB)
        #expect(result.triangleCount == 0)
    }

    @Test("Difference of separated cubes preserves A")
    func differenceSeparated() {
        let (a, b) = separatedCubes()
        let soupA = TriangleSoup(mesh: a)
        let soupB = TriangleSoup(mesh: b)
        let result = soupA.difference(soupB)
        #expect(result.triangleCount == soupA.triangleCount)
    }

    // MARK: - Mesh CSG API

    @Test("Mesh.union produces valid mesh")
    func meshUnion() {
        let (a, b) = overlappingCubes()
        let result = a.union(b)
        #expect(result.faceCount > 0)
        #expect(result.vertexCount > 0)
    }

    @Test("Mesh.intersection produces valid mesh")
    func meshIntersection() {
        let (a, b) = overlappingCubes()
        let result = a.intersection(b)
        #expect(result.faceCount > 0)
        #expect(result.vertexCount > 0)
    }

    @Test("Mesh.difference produces valid mesh")
    func meshDifference() {
        let (a, b) = overlappingCubes()
        let result = a.difference(b)
        #expect(result.faceCount > 0)
        #expect(result.vertexCount > 0)
    }

    // MARK: - Volume sanity checks

    @Test("Union volume is larger than either input")
    func unionVolumeGrows() {
        let (a, b) = overlappingCubes()
        let result = a.union(b)
        let boundsA = a.bounds
        let boundsResult = result.bounds
        let volumeA = (boundsA.max.x - boundsA.min.x) * (boundsA.max.y - boundsA.min.y) * (boundsA.max.z - boundsA.min.z)
        let volumeResult = (boundsResult.max.x - boundsResult.min.x) * (boundsResult.max.y - boundsResult.min.y) * (boundsResult.max.z - boundsResult.min.z)
        #expect(volumeResult >= volumeA - 0.01)
    }

    @Test("Intersection bounding box is smaller than either input")
    func intersectionBoundsShrink() {
        let (a, b) = overlappingCubes()
        let result = a.intersection(b)
        let boundsA = a.bounds
        let boundsResult = result.bounds
        let sizeA = boundsA.max - boundsA.min
        let sizeResult = boundsResult.max - boundsResult.min
        // Intersection should be smaller or equal on every axis
        #expect(sizeResult.x <= sizeA.x + 0.01)
        #expect(sizeResult.y <= sizeA.y + 0.01)
        #expect(sizeResult.z <= sizeA.z + 0.01)
    }

    @Test("Difference bounding box fits within original")
    func differenceBoundsWithin() {
        let (a, b) = overlappingCubes()
        let result = a.difference(b)
        let boundsA = a.bounds
        let boundsResult = result.bounds
        #expect(boundsResult.min.x >= boundsA.min.x - 0.01)
        #expect(boundsResult.min.y >= boundsA.min.y - 0.01)
        #expect(boundsResult.min.z >= boundsA.min.z - 0.01)
        #expect(boundsResult.max.x <= boundsA.max.x + 0.01)
        #expect(boundsResult.max.y <= boundsA.max.y + 0.01)
        #expect(boundsResult.max.z <= boundsA.max.z + 0.01)
    }

    // MARK: - Edge cases

    @Test("CSG with empty soup")
    func csgWithEmpty() {
        let cube = TriangleSoup(mesh: Mesh.box(extents: [1, 1, 1], attributes: []))
        let empty = TriangleSoup()

        let unionResult = cube.union(empty)
        #expect(unionResult.triangleCount == cube.triangleCount)

        let interResult = cube.intersection(empty)
        #expect(interResult.triangleCount == 0)

        let diffResult = cube.difference(empty)
        #expect(diffResult.triangleCount == cube.triangleCount)
    }

    @Test("Union with sphere and cube")
    func sphereCubeUnion() {
        let sphere = Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 1, attributes: [])
        let cube = Mesh.box(extents: [0.8, 0.8, 0.8], attributes: [])
        let result = sphere.union(cube)
        #expect(result.faceCount > 0)
    }

    @Test("Difference sphere minus cube")
    func sphereMinusCube() {
        let sphere = Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 1, attributes: [])
        let cube = Mesh.box(extents: [0.8, 0.8, 0.8], attributes: [])
        let result = sphere.difference(cube)
        #expect(result.faceCount > 0)
    }
}
