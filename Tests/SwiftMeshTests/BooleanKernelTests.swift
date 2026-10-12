import simd
@testable import SwiftMesh
import Testing

@Suite("Boolean kernels")
struct BooleanKernelTests {
    private func boolean(_ mesh: Mesh) throws -> BooleanMesh {
        try BooleanMesh(mesh: mesh)
    }

    /// Möller-Trumbore segment vs triangle; returns the point if it crosses the interior.
    private func segmentHitsTriangle(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ t0: SIMD3<Double>, _ t1: SIMD3<Double>, _ t2: SIMD3<Double>) -> SIMD3<Double>? {
        let direction = b - a
        let e1 = t1 - t0
        let e2 = t2 - t0
        let p = simd_cross(direction, e2)
        let det = simd_dot(e1, p)
        guard abs(det) > 1e-14 else {
            return nil
        }
        let s = a - t0
        let u = simd_dot(s, p) / det
        let q = simd_cross(s, e1)
        let v = simd_dot(direction, q) / det
        let t = simd_dot(e2, q) / det
        guard u > 0, v > 0, u + v < 1, t > 0, t < 1 else {
            return nil
        }
        return a + t * direction
    }

    /// Forward edges of A against faces of B by brute force, as [edge: [face: point]].
    private func bruteForce(edgesOf a: BooleanMesh, facesOf b: BooleanMesh) -> [SIMD2<Int>: SIMD3<Double>] {
        var result: [SIMD2<Int>: SIMD3<Double>] = [:]
        for (edge, halfedge) in a.halfedges.enumerated() where halfedge.startVert < halfedge.endVert {
            for face in 0..<b.numTri {
                let corners = (0..<3).map { b.vertPos[b.halfedges[3 * face + $0].startVert] }
                if let point = segmentHitsTriangle(a.vertPos[halfedge.startVert], a.vertPos[halfedge.endVert], corners[0], corners[1], corners[2]) {
                    result[SIMD2(edge, face)] = point
                }
            }
        }
        return result
    }

    @Test("Generic position: crossings match brute force in both directions", arguments: [true, false])
    func generic(expandP: Bool) throws {
        let rotation = simd_float4x4(simd_quatf(angle: 0.7, axis: simd_normalize([1, 2, 3])))
        let p = try boolean(Mesh.icoSphere(extents: [0.9, 0.9, 0.9], subdivisions: 2, attributes: []).transformed(by: rotation).translated(by: [0.13, 0.07, 0.05]))
        let q = try boolean(Mesh.torus(attributes: []))
        let kernels = BooleanKernels(inP: p, inQ: q, expandP: expandP)

        let forward = kernels.intersect12(forward: true, colliderB: q.makeFaceCollider())
        let expectedForward = bruteForce(edgesOf: p, facesOf: q)
        #expect(Set(forward.p1q2) == Set(expectedForward.keys))
        for (index, pair) in forward.p1q2.enumerated() {
            #expect(abs(forward.x12[index]) == 1)
            if let point = expectedForward[pair] {
                #expect(simd_distance(point, forward.v12[index]) < 1e-9)
            }
        }

        let reverse = kernels.intersect12(forward: false, colliderB: p.makeFaceCollider())
        let expectedReverse = bruteForce(edgesOf: q, facesOf: p)
        // Reverse pairs are stored as (P face, Q edge).
        #expect(Set(reverse.p1q2.map { SIMD2($0.y, $0.x) }) == Set(expectedReverse.keys))
        for (index, pair) in reverse.p1q2.enumerated() {
            if let point = expectedReverse[SIMD2(pair.y, pair.x)] {
                #expect(simd_distance(point, reverse.v12[index]) < 1e-9)
            }
        }
        // Sorted by the A index, then the B index.
        #expect(forward.p1q2 == forward.p1q2.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y })
        #expect(reverse.p1q2 == reverse.p1q2.sorted { $0.y != $1.y ? $0.y < $1.y : $0.x < $1.x })
    }

    @Test("Degenerate: identical meshes separate when P is contracted (difference/intersection)")
    func identicalContracted() throws {
        for mesh in [Mesh.cube(attributes: []), Mesh.icoSphere(subdivisions: 1, attributes: [])] {
            let p = try boolean(mesh)
            let kernels = BooleanKernels(inP: p, inQ: p, expandP: false)
            #expect(kernels.intersect12(forward: true, colliderB: p.makeFaceCollider()).p1q2.isEmpty)
            #expect(kernels.intersect12(forward: false, colliderB: p.makeFaceCollider()).p1q2.isEmpty)
        }
    }

    @Test("Degenerate: identical meshes under union perturbation give finite, assert-free crossings")
    func identicalExpanded() throws {
        // Union expands both inputs, so they still coincide; ties are broken symbolically.
        for mesh in [Mesh.cube(attributes: []), Mesh.icoSphere(subdivisions: 1, attributes: [])] {
            let p = try boolean(mesh)
            let kernels = BooleanKernels(inP: p, inQ: p, expandP: true)
            let forward = kernels.intersect12(forward: true, colliderB: p.makeFaceCollider())
            #expect(forward.v12.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
            #expect(forward.x12.allSatisfy { abs($0) == 1 })
        }
    }

    @Test("Degenerate: touching and coplanar cubes run without kernel inconsistencies", arguments: [true, false])
    func touching(expandP: Bool) throws {
        let cube = Mesh.cube(attributes: [])
        let cases: [Mesh] = [
            cube.translated(by: [1, 0, 0]),       // face-to-face contact
            cube.translated(by: [0.5, 0, 0]),     // overlapping with coplanar top/bottom/front/back faces
            cube.translated(by: [0.5, 0.5, 0]),   // shared coplanar faces, offset two ways
            cube.translated(by: [1, 1, 1])        // single vertex contact
        ]
        let p = try boolean(cube)
        for other in cases {
            let q = try boolean(other)
            let kernels = BooleanKernels(inP: p, inQ: q, expandP: expandP)
            let forward = kernels.intersect12(forward: true, colliderB: q.makeFaceCollider())
            let reverse = kernels.intersect12(forward: false, colliderB: p.makeFaceCollider())
            #expect(forward.v12.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
            #expect(reverse.v12.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        }
    }
}
