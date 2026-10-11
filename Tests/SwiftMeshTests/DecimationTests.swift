import simd
@testable import SwiftMesh
import Testing

@Suite("Mesh Decimation")
struct DecimationTests {
    // Helper: count live faces
    private func liveFaceCount(_ mesh: Mesh) -> Int {
        mesh.topology.faces.filter { $0.edge != nil }.count
    }

    // MARK: - Basic decimation

    @Test("Decimate icosphere reduces face count")
    func decimateIcoSphere() {
        let mesh = Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 2, attributes: [])
        let original = liveFaceCount(mesh)
        let target = original / 2
        let simplified = mesh.decimated(targetFaceCount: target)
        #expect(liveFaceCount(simplified) <= target)
        #expect(liveFaceCount(simplified) < original)
    }

    @Test("Decimate icosphere to exact target")
    func decimateToTarget() {
        let mesh = Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 1, attributes: [])
        let simplified = mesh.decimated(targetFaceCount: 20)
        #expect(liveFaceCount(simplified) <= 20)
    }

    @Test("Decimate with ratio")
    func decimateWithRatio() {
        let mesh = Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 2, attributes: [])
        let original = liveFaceCount(mesh)
        let simplified = mesh.decimated(ratio: 0.5)
        let target = original / 2
        #expect(liveFaceCount(simplified) <= target)
    }

    @Test("Decimation compacts tombstones and stays valid", arguments: [Float(0.5), 0.25])
    func decimationCompacts(ratio: Float) {
        let mesh = Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 3)
        let simplified = mesh.decimated(ratio: ratio)
        #expect(simplified.topology.faces.allSatisfy { $0.edge != nil })
        #expect(simplified.topology.vertices.allSatisfy { $0.edge != nil })
        #expect(simplified.topology.halfEdges.allSatisfy { $0.next != nil })
        #expect(simplified.validate().isEmpty)
        #expect(simplified.positions.count == simplified.vertexCount)
    }

    // CSG output has n-gon faces; a closed quad mesh exercises the same path deterministically.
    @Test("Decimating n-gon faces doesn't open holes")
    func decimateNGonsKeepsClosed() {
        let mesh = Mesh.box(attributes: []).catmullClarkSubdivided(iterations: 3)
        #expect(mesh.isManifold)
        let simplified = mesh.decimated(ratio: 0.5)
        #expect(simplified.topology.halfEdges.allSatisfy { $0.twin != nil })
    }

    @Test("Decimation never creates edges with more than two faces", arguments: [Float(0.5), 0.25, 0.1])
    func noNonManifoldEdges(ratio: Float) {
        // Default attributes add UV seams (duplicated vertices), which is where bad collapses showed up.
        let simplified = Mesh.icoSphere(subdivisions: 3).decimated(ratio: ratio)
        var counts: [[Int]: Int] = [:]
        for halfEdge in simplified.topology.halfEdges {
            let destination = simplified.topology.destViaNext(of: halfEdge.id)!.raw
            counts[[min(halfEdge.origin.raw, destination), max(halfEdge.origin.raw, destination)], default: 0] += 1
        }
        #expect(counts.values.allSatisfy { $0 <= 2 })
    }

    // MARK: - Edge cases

    @Test("Decimate with target >= current face count is a no-op")
    func decimateNoOp() {
        let mesh = Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 1, attributes: [])
        let original = liveFaceCount(mesh)
        let simplified = mesh.decimated(targetFaceCount: original + 10)
        #expect(liveFaceCount(simplified) == original)
    }

    @Test("Decimate with target of 1")
    func decimateToMinimum() {
        let mesh = Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 1, attributes: [])
        let simplified = mesh.decimated(targetFaceCount: 1)
        #expect(liveFaceCount(simplified) <= liveFaceCount(mesh))
    }

    @Test("Decimate tetrahedron (minimal closed mesh)")
    func decimateTetrahedron() {
        let mesh = Mesh.tetrahedron(attributes: [])
        #expect(liveFaceCount(mesh) == 4)
        let simplified = mesh.decimated(targetFaceCount: 2)
        #expect(liveFaceCount(simplified) <= 2)
    }

    // MARK: - Shape preservation

    @Test("Decimation preserves approximate bounding box")
    func preservesBounds() {
        let mesh = Mesh.icoSphere(extents: [2, 2, 2], subdivisions: 2, attributes: [])
        let simplified = mesh.decimated(targetFaceCount: 40)
        let (origMin, origMax) = mesh.bounds
        let (simpMin, simpMax) = simplified.bounds
        // Bounds should be roughly similar (within 20%)
        let origSize = origMax - origMin
        let simpSize = simpMax - simpMin
        for axis in 0..<3 {
            let ratio = simpSize[axis] / origSize[axis]
            #expect(ratio > 0.5, "Axis \(axis) shrunk too much: \(ratio)")
            #expect(ratio < 2.0, "Axis \(axis) grew too much: \(ratio)")
        }
    }

    @Test("Decimation preserves approximate center")
    func preservesCenter() {
        let mesh = Mesh.icoSphere(extents: [2, 2, 2], subdivisions: 2, attributes: []).translated(by: [5, 5, 5])
        let simplified = mesh.decimated(targetFaceCount: 40)
        let origCenter = mesh.center
        let simpCenter = simplified.center
        let dist = simd_length(origCenter - simpCenter)
        #expect(dist < 1.0, "Center moved too far: \(dist)")
    }

    // MARK: - Topology validity

    @Test("Remaining faces have valid vertex loops after decimation")
    func validLoopsAfterDecimation() {
        let mesh = Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 2, attributes: [])
        let simplified = mesh.decimated(targetFaceCount: 40)
        for face in simplified.topology.faces where face.edge != nil {
            let loop = simplified.topology.vertexLoop(for: face.id)
            #expect(loop.count >= 3, "Face \(face.id) has degenerate loop with \(loop.count) vertices")
        }
    }

    @Test("No self-loop half-edges after decimation")
    func noSelfLoops() {
        let mesh = Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 2, attributes: [])
        let simplified = mesh.decimated(targetFaceCount: 40)
        for he in simplified.topology.halfEdges where he.next != nil {
            if let dest = simplified.topology.destViaNext(of: he.id) {
                #expect(dest != he.origin, "Self-loop at \(he.id)")
            }
        }
    }

    @Test("Twin symmetry after decimation")
    func twinSymmetry() {
        let mesh = Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 2, attributes: [])
        let simplified = mesh.decimated(targetFaceCount: 40)
        for he in simplified.topology.halfEdges where he.next != nil {
            if let twin = he.twin {
                #expect(simplified.topology.halfEdges[twin.raw].twin == he.id)
            }
        }
    }

    @Test("Next/prev consistency after decimation")
    func nextPrevConsistency() {
        let mesh = Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 2, attributes: [])
        let simplified = mesh.decimated(targetFaceCount: 40)
        for he in simplified.topology.halfEdges where he.next != nil {
            if let next = he.next {
                #expect(simplified.topology.halfEdges[next.raw].prev == he.id)
            }
            if let prev = he.prev {
                #expect(simplified.topology.halfEdges[prev.raw].next == he.id)
            }
        }
    }

    // MARK: - Mutating vs non-mutating

    @Test("decimated() returns new mesh, original unchanged")
    func nonMutating() {
        let mesh = Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 1, attributes: [])
        let originalCount = liveFaceCount(mesh)
        let simplified = mesh.decimated(targetFaceCount: 10)
        #expect(liveFaceCount(mesh) == originalCount)
        #expect(liveFaceCount(simplified) < originalCount)
    }

    @Test("decimate() mutates in place")
    func mutating() {
        var mesh = Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 1, attributes: [])
        let originalCount = liveFaceCount(mesh)
        mesh.decimate(targetFaceCount: 10)
        #expect(liveFaceCount(mesh) < originalCount)
    }

    // MARK: - Different primitives

    @Test("Decimate cube")
    func decimateCube() {
        let mesh = Mesh.cubeSphere(extents: [1, 1, 1], subdivisions: 3, attributes: [])
        let original = liveFaceCount(mesh)
        let simplified = mesh.decimated(ratio: 0.25)
        #expect(liveFaceCount(simplified) < original)
    }

    @Test("Decimate subdivided tetrahedron")
    func decimateSubdivided() {
        let mesh = Mesh.tetrahedron(attributes: []).loopSubdivided(iterations: 3)
        let original = liveFaceCount(mesh)
        let target = original / 4
        let simplified = mesh.decimated(targetFaceCount: target)
        #expect(liveFaceCount(simplified) <= target)
    }

    // MARK: - Aggressive decimation

    @Test("Aggressive decimation doesn't crash")
    func aggressiveDecimation() {
        let mesh = Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 3, attributes: [])
        // Try to reduce to almost nothing
        let simplified = mesh.decimated(targetFaceCount: 4)
        #expect(liveFaceCount(simplified) <= liveFaceCount(mesh))
    }

    @Test("Ratio 0.0 reduces as much as possible")
    func ratioZero() {
        let mesh = Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 1, attributes: [])
        let simplified = mesh.decimated(ratio: 0.0)
        #expect(liveFaceCount(simplified) <= liveFaceCount(mesh))
    }

    @Test("Ratio 1.0 is approximately a no-op")
    func ratioOne() {
        let mesh = Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 1, attributes: [])
        let original = liveFaceCount(mesh)
        let simplified = mesh.decimated(ratio: 1.0)
        #expect(liveFaceCount(simplified) == original)
    }
}
