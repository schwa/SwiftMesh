import simd
@testable import SwiftMesh
import Testing

@Suite("Edge loop")
struct EdgeLoopTests {
    private func vertices(of loop: [HalfEdgeTopology.HalfEdgeID], in topology: HalfEdgeTopology) -> Set<Int> {
        Set(loop.flatMap { [topology.halfEdges[$0.raw].origin.raw, topology.destViaNext(of: $0)!.raw] })
    }

    @Test("Torus loops close around the major and minor circles")
    func torus() {
        let topology = Mesh.torus(majorSegments: 12, minorSegments: 8, attributes: []).topology
        let lengths = Set(topology.halfEdges.prefix(4).map { topology.edgeLoop(from: $0.id).count })
        // Every edge lies on a closed loop of either 12 (around the major circle) or 8 (minor).
        #expect(lengths.isSubset(of: [8, 12]))
        for halfEdge in topology.halfEdges.prefix(20) {
            let loop = topology.edgeLoop(from: halfEdge.id)
            #expect(loop.contains(halfEdge.id))
            #expect(Set(loop).count == loop.count)
            // Closed: each vertex is used by exactly two loop edges.
            #expect(vertices(of: loop, in: topology).count == loop.count)
        }
    }

    @Test("A UV sphere's meridian loop runs pole to pole")
    func sphereMeridian() {
        let mesh = Mesh.sphere(latitudeSegments: 6, longitudeSegments: 8, attributes: [])
        let topology = mesh.topology
        // A meridian edge away from the poles: both ends at the same angle around y.
        let meridian = topology.halfEdges.first { halfEdge in
            let a = mesh.positions[halfEdge.origin.raw]
            let b = mesh.positions[topology.destViaNext(of: halfEdge.id)!.raw]
            let sameAngle = abs(atan2(a.z, a.x) - atan2(b.z, b.x)) < 1e-4
            return sameAngle && abs(a.y - b.y) > 1e-3 && abs(abs(a.y) - 0.5) > 1e-3 && abs(abs(b.y) - 0.5) > 1e-3
        }!
        let loop = topology.edgeLoop(from: meridian.id)
        #expect(loop.count == 6) // pole to pole through 5 latitude rings
        let ys = vertices(of: loop, in: topology).map { mesh.positions[$0].y }
        #expect(ys.contains { abs($0 - 0.5) < 1e-5 })
        #expect(ys.contains { abs($0 + 0.5) < 1e-5 })
    }

    @Test("An interior row of a quad grid stops at the boundary")
    func gridBorder() {
        // 3 x 2 quads.
        var positions: [SIMD3<Float>] = []
        for y in 0...2 { for x in 0...3 { positions.append([Float(x), Float(y), 0]) } }
        var faces: [[Int]] = []
        for y in 0..<2 { for x in 0..<3 { let i = y * 4 + x; faces.append([i, i + 1, i + 5, i + 4]) } }
        let topology = Mesh(positions: positions, faces: faces).topology
        // A horizontal edge on the middle row (5 -> 6); the loop runs the row and stops at the grid's sides.
        let middle = topology.halfEdges.first { $0.origin.raw == 5 && topology.destViaNext(of: $0.id)!.raw == 6 }!
        let loop = topology.edgeLoop(from: middle.id)
        #expect(vertices(of: loop, in: topology) == [4, 5, 6, 7])
    }
}
