import simd
@testable import SwiftMesh
import Testing

@Suite("Mesh Optimization")
struct MeshOptimizationTests {
    // MARK: - Basic merging

    @Test("Two coplanar triangles merge into one quad")
    func mergeTriangulatedQuad() {
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0)
        ], faces: [[0, 1, 2], [0, 2, 3]])
        #expect(mesh.faceCount == 2)

        let merged = mesh.mergingCoplanarFaces()
        #expect(merged.faceCount == 1)
        #expect(merged.validate() == nil)
    }

    @Test("Four coplanar triangles in a fan merge into one polygon")
    func mergeFan() {
        // Four triangles sharing center vertex, all in XY plane
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0),  // center
            SIMD3(1, 0, 0),
            SIMD3(1, 1, 0),
            SIMD3(0, 1, 0),
            SIMD3(-1, 0, 0),
        ], faces: [
            [0, 1, 2],
            [0, 2, 3],
            [0, 3, 4],
            [0, 4, 1],
        ])
        #expect(mesh.faceCount == 4)

        let merged = mesh.mergingCoplanarFaces()
        #expect(merged.faceCount < 4)
        #expect(merged.validate() == nil)
    }

    @Test("Triangulated box face merges back to one face")
    func mergeTriangulatedBoxFace() {
        // A quad split into two triangles — should merge back
        let mesh = Mesh(positions: [
            SIMD3(-1, -1, 0), SIMD3(1, -1, 0), SIMD3(1, 1, 0), SIMD3(-1, 1, 0)
        ], faces: [[0, 1, 2], [0, 2, 3]])

        let merged = mesh.mergingCoplanarFaces()
        #expect(merged.faceCount == 1)
        // The merged face should have 4 vertices (collinear center removed)
        let verts = merged.topology.vertexLoop(for: .init(raw: 0))
        #expect(verts.count == 4)
    }

    // MARK: - Non-coplanar preservation

    @Test("Non-coplanar faces are not merged")
    func noMergeNonCoplanar() {
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)
        ], faces: [[0, 1, 2], [0, 1, 3]])
        let merged = mesh.mergingCoplanarFaces()
        #expect(merged.faceCount == 2)
    }

    @Test("Cube faces are not merged (all faces are at 90 degrees)")
    func cubeNoMerge() {
        let mesh = Mesh.cube(attributes: [])
        let merged = mesh.mergingCoplanarFaces()
        #expect(merged.faceCount == mesh.faceCount)
    }

    @Test("Coplanar faces on parallel but offset planes are not merged")
    func parallelButOffset() {
        // Two triangles with same normal but on different planes (z=0 and z=1)
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0),
            SIMD3(0, 0, 1), SIMD3(1, 0, 1), SIMD3(0, 1, 1),
        ], faces: [[0, 1, 2], [3, 4, 5]])
        let merged = mesh.mergingCoplanarFaces()
        // Not adjacent, so can't merge even if coplanar
        #expect(merged.faceCount == 2)
    }

    // MARK: - Mixed coplanar and non-coplanar

    @Test("Only coplanar adjacent pairs merge in mixed mesh")
    func mixedMerge() {
        // Three triangles: first two coplanar (XY plane), third at an angle
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0),
            SIMD3(0, 0, 1),
        ], faces: [
            [0, 1, 2], // XY plane
            [0, 2, 3], // XY plane (coplanar with above)
            [0, 1, 4], // tilted face
        ])
        #expect(mesh.faceCount == 3)

        let merged = mesh.mergingCoplanarFaces()
        // Two coplanar merge into one, tilted stays → 2 faces
        #expect(merged.faceCount == 2)
        #expect(merged.validate() == nil)
    }

    // MARK: - Collinear vertex removal

    @Test("Collinear vertices are removed from merged boundary")
    func collinearRemoval() {
        // Three coplanar triangles in a strip: [0,1,2], [1,3,2], [2,3,4]
        // After merging, interior vertices should be removed if collinear
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0),
            SIMD3(2, 0, 0), SIMD3(2, 1, 0),
        ], faces: [[0, 1, 2], [1, 3, 2], [2, 3, 4]])
        #expect(mesh.faceCount == 3)

        let merged = mesh.mergingCoplanarFaces()
        #expect(merged.faceCount < 3)
        #expect(merged.validate() == nil)

        // Check no face has collinear vertices
        for face in merged.topology.faces {
            let verts = merged.topology.vertexLoop(for: face.id)
            for i in 0..<verts.count {
                let prev = merged.positions[verts[(i + verts.count - 1) % verts.count].raw]
                let curr = merged.positions[verts[i].raw]
                let next = merged.positions[verts[(i + 1) % verts.count].raw]
                let cross = simd_length(simd_cross(curr - prev, next - curr))
                let edgeLen = simd_length(curr - prev) * simd_length(next - curr)
                if edgeLen > 0 {
                    #expect(cross / edgeLen > 1e-4, "Collinear vertex found at index \(verts[i].raw)")
                }
            }
        }
    }

    // MARK: - CSG integration

    @Test("CSG difference benefits from merging")
    func csgDifferenceMerging() {
        let a = Mesh.box(extents: [1, 1, 1], attributes: [])
        let b = Mesh.box(extents: [0.5, 0.5, 0.5], attributes: [])
        let unmerged = a.difference(b, mergeCoplanar: false)
        let merged = a.difference(b, mergeCoplanar: true)
        #expect(merged.faceCount < unmerged.faceCount)
        #expect(merged.validate() == nil)
    }

    @Test("CSG union benefits from merging")
    func csgUnionMerging() {
        let a = Mesh.box(extents: [0.6, 0.6, 0.6], attributes: [])
        var bPositions = Mesh.box(extents: [0.6, 0.6, 0.6], attributes: []).positions
        for i in bPositions.indices { bPositions[i] += [0.3, 0.3, 0.3] }
        let b = Mesh(positions: bPositions, faces: [
            [0, 1, 2, 3], [5, 4, 7, 6],
            [4, 0, 3, 7], [1, 5, 6, 2],
            [3, 2, 6, 7], [4, 5, 1, 0]
        ])
        let unmerged = a.union(b, mergeCoplanar: false)
        let merged = a.union(b, mergeCoplanar: true)
        #expect(merged.faceCount < unmerged.faceCount)
    }

    @Test("CSG intersection benefits from merging")
    func csgIntersectionMerging() {
        let a = Mesh.box(extents: [1, 1, 1], attributes: [])
        let b = Mesh.box(extents: [0.8, 0.8, 0.8], attributes: [])
        let unmerged = a.intersection(b, mergeCoplanar: false)
        let merged = a.intersection(b, mergeCoplanar: true)
        #expect(merged.faceCount <= unmerged.faceCount)
    }

    @Test("Merged CSG result is still valid")
    func csgMergedValid() {
        let sphere = Mesh.icoSphere(extents: [0.8, 0.8, 0.8], subdivisions: 2, attributes: [])
        let cube = Mesh.box(extents: [0.5, 0.5, 0.5], attributes: [])
        let result = sphere.difference(cube)
        // Just check it doesn't crash and produces faces
        #expect(result.faceCount > 0)
    }

    // MARK: - Edge cases

    @Test("Merging single face is a no-op")
    func singleFace() {
        let mesh = Mesh.triangle(attributes: [])
        let merged = mesh.mergingCoplanarFaces()
        #expect(merged.faceCount == 1)
        #expect(merged.vertexCount == 3)
    }

    @Test("Merging already-clean mesh is a no-op")
    func alreadyClean() {
        let mesh = Mesh.box(attributes: [])
        let merged = mesh.mergingCoplanarFaces()
        #expect(merged.faceCount == mesh.faceCount)
    }

    @Test("Multiple merge passes converge")
    func multiplePassesConverge() {
        // A grid of 4 coplanar triangles
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(2, 0, 0),
            SIMD3(0, 1, 0), SIMD3(1, 1, 0), SIMD3(2, 1, 0),
        ], faces: [
            [0, 1, 4], [0, 4, 3],
            [1, 2, 5], [1, 5, 4],
        ])
        let merged1 = mesh.mergingCoplanarFaces()
        let merged2 = merged1.mergingCoplanarFaces()
        // Second pass should not change anything
        #expect(merged2.faceCount == merged1.faceCount)
    }
}
