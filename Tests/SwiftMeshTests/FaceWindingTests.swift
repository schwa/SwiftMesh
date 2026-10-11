import simd
@testable import SwiftMesh
import Testing

@Suite("Face winding consistency")
struct FaceWindingTests {
    /// Icosphere with some faces reversed (built from face definitions so the flips stay unpaired).
    private func scrambled(_ flipped: Set<Int>) -> Mesh {
        let sphere = Mesh.icoSphere(subdivisions: 1, attributes: [])
        let faces = sphere.topology.faces.map { face in
            let loop = sphere.topology.vertexLoop(for: face.id).map(\.raw)
            return flipped.contains(face.id.raw) ? Array(loop.reversed()) : loop
        }
        return Mesh(positions: sphere.positions, faces: faces)
    }

    @Test("Consistent closed mesh reports nothing to flip")
    func consistent() {
        let mesh = Mesh.icoSphere(subdivisions: 1, attributes: [])
        #expect(!mesh.topology.hasInconsistentFaceWinding)
        #expect(mesh.topology.facesToFlipForConsistentWinding() == [])
    }

    @Test("Reversed faces are found and repaired to a closed manifold")
    func repaired() throws {
        let mesh = scrambled([0, 5, 17])
        #expect(mesh.topology.hasInconsistentFaceWinding)
        #expect(mesh.topology.inconsistentWindingEdges().count == 9) // three triangles, three edges each
        #expect(!mesh.isManifold)
        #expect(mesh.topology.facesToFlipForConsistentWinding() == [0, 5, 17].map { HalfEdgeTopology.FaceID(raw: $0) }.reduce(into: Set()) { $0.insert($1) })

        let fixed = try #require(mesh.withConsistentWinding())
        #expect(!fixed.topology.hasInconsistentFaceWinding)
        #expect(fixed.isManifold)
        let center = fixed.center
        #expect(fixed.topology.faces.allSatisfy { simd_dot(fixed.faceNormal($0.id), fixed.faceCentroid($0.id) - center) > 0 })
    }

    @Test("Boundary edges are not counted as inconsistent")
    func boundary() {
        let quad = Mesh(positions: [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]], faces: [[0, 1, 2], [0, 2, 3]])
        #expect(!quad.topology.hasInconsistentFaceWinding)
        let flipped = Mesh(positions: quad.positions, faces: [[0, 1, 2], [3, 2, 0]])
        #expect(flipped.topology.inconsistentWindingEdges().count == 1)
    }

    @Test("Möbius strip cannot be made consistent")
    func mobius() {
        let segments = 8
        var positions: [SIMD3<Float>] = []
        for index in 0..<segments {
            let angle = Float(index) / Float(segments) * 2 * .pi
            let twist = angle / 2
            let offset = SIMD3<Float>(cos(angle) * cos(twist), sin(angle) * cos(twist), sin(twist)) * 0.3
            positions += [SIMD3(cos(angle), sin(angle), 0) - offset, SIMD3(cos(angle), sin(angle), 0) + offset]
        }
        var faces = (0..<(segments - 1)).map { [2 * $0, 2 * $0 + 2, 2 * $0 + 3, 2 * $0 + 1] }
        faces.append([2 * (segments - 1), 1, 0, 2 * (segments - 1) + 1])
        let mesh = Mesh(positions: positions, faces: faces)
        #expect(mesh.topology.hasInconsistentFaceWinding)
        #expect(mesh.topology.facesToFlipForConsistentWinding() == nil)
        #expect(mesh.withConsistentWinding() == nil)
    }

    @Test("reversingWinding(of:) flips only the given faces")
    func partialReverse() {
        let mesh = scrambled([3])
        let fixed = mesh.reversingWinding(of: [HalfEdgeTopology.FaceID(raw: 3)])
        #expect(!fixed.topology.hasInconsistentFaceWinding)
        #expect(fixed.topology.vertexLoop(for: .init(raw: 0)) == mesh.topology.vertexLoop(for: .init(raw: 0)))
    }
}
