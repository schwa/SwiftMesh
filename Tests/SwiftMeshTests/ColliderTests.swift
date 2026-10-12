import simd
@testable import SwiftMesh
import Testing

@Suite("Boolean collider")
struct ColliderTests {
    private func edgeBoxes(_ mesh: BooleanMesh) -> [BooleanBox] {
        mesh.halfedges.map { edge in
            edge.startVert < edge.endVert ? BooleanBox(mesh.vertPos[edge.startVert], mesh.vertPos[edge.endVert]) : BooleanBox()
        }
    }

    private func faceBoxes(_ mesh: BooleanMesh) -> [BooleanBox] {
        (0..<mesh.numTri).map { triangle in
            var box = BooleanBox()
            for corner in 0..<3 {
                box.union(mesh.vertPos[mesh.halfedges[3 * triangle + corner].startVert])
            }
            return box
        }
    }

    @Test("Edge-box queries match brute force")
    func edgeQueries() throws {
        let p = try BooleanMesh(mesh: .icoSphere(subdivisions: 2, attributes: []).transformed(by: simd_float4x4(simd_quatf(angle: 0.4, axis: simd_normalize([1, 2, 3])))).translated(by: [0.2, 0.1, 0]))
        let q = try BooleanMesh(mesh: .torus(attributes: []))
        let collider = q.makeFaceCollider()
        let faces = faceBoxes(q)
        for (index, query) in edgeBoxes(p).enumerated() {
            var found = Set<Int>()
            collider.forEachOverlap(query) { found.insert($0) }
            let expected = query.isEmpty ? [] : Set(faces.indices.filter { faces[$0].overlaps(query) })
            #expect(found == expected, "edge \(index)")
        }
    }

    @Test("XY point queries match brute force")
    func pointQueries() throws {
        let q = try BooleanMesh(mesh: .icoSphere(subdivisions: 2, attributes: []))
        let collider = q.makeFaceCollider()
        let faces = faceBoxes(q)
        var state: UInt64 = 3
        for _ in 0..<300 {
            func next() -> Double {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double(state >> 11) / Double(1 << 53) * 1.4 - 0.7
            }
            let point = SIMD3(next(), next(), next())
            var found = Set<Int>()
            collider.forEachOverlapXY(point) { found.insert($0) }
            #expect(found == Set(faces.indices.filter { faces[$0].overlapsXY(point) }))
        }
    }

    @Test("Bounding box covers all leaves")
    func bounds() throws {
        let mesh = try BooleanMesh(mesh: .torus(attributes: []))
        let box = mesh.makeFaceCollider().boundingBox
        #expect(simd_length(box.min - mesh.boundsMin) < 1e-12)
        #expect(simd_length(box.max - mesh.boundsMax) < 1e-12)
    }

    @Test("Edge cases: single leaf, identical Morton codes, empty query")
    func edgeCases() {
        let single = Collider(boxes: [BooleanBox([0, 0, 0], [1, 1, 1])], mortonCodes: [5])
        var hits: [Int] = []
        single.forEachOverlap(BooleanBox([0.5, 0.5, 0.5], [2, 2, 2])) { hits.append($0) }
        #expect(hits == [0])

        // Many leaves with the same code (disambiguated by index).
        let boxes = (0..<50).map { BooleanBox([Double($0), 0, 0], [Double($0) + 0.5, 1, 1]) }
        let same = Collider(boxes: boxes, mortonCodes: [UInt32](repeating: 7, count: 50))
        var found = Set<Int>()
        same.forEachOverlap(BooleanBox([10.25, 0, 0], [12.25, 1, 1])) { found.insert($0) }
        #expect(found == [10, 11, 12])

        var none = 0
        same.forEachOverlap(BooleanBox()) { _ in none += 1 }
        #expect(none == 0)
    }
}
