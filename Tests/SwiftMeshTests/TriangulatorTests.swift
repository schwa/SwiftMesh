import Foundation
import simd
@testable import SwiftMesh
import Testing

@Suite("Robust triangulator")
struct TriangulatorTests {
    struct CorpusEntry: Sendable, CustomTestStringConvertible {
        var name: String
        var expectedTriangles: Int
        var epsilon: Double
        var polygons: [[SIMD2<Double>]]
        var testDescription: String { name }
    }

    /// Reads Manifold's polygon corpus format: "name expectedNumTri epsilon numPolys", then
    /// for each polygon a vertex count followed by "x y" lines.
    static func corpus(_ file: String) -> [CorpusEntry] {
        guard let url = Bundle.module.url(forResource: file, withExtension: "txt", subdirectory: "ManifoldPolygons"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        var tokens = text.split(whereSeparator: \.isWhitespace).makeIterator()
        var entries: [CorpusEntry] = []
        while let name = tokens.next() {
            guard let expected = tokens.next().flatMap({ Int($0) }),
                  let epsilon = tokens.next().flatMap({ Double($0) }),
                  let polygonCount = tokens.next().flatMap({ Int($0) }) else {
                break
            }
            var polygons: [[SIMD2<Double>]] = []
            for _ in 0..<polygonCount {
                let count = Int(tokens.next()!)!
                polygons.append((0..<count).map { _ in SIMD2(Double(tokens.next()!)!, Double(tokens.next()!)!) })
            }
            entries.append(CorpusEntry(name: String(name), expectedTriangles: expected, epsilon: epsilon, polygons: polygons))
        }
        return entries
    }

    static let mainCorpus = corpus("polygon_corpus")
    static let spongeCorpus = corpus("sponge")

    private func indexed(_ polygons: [[SIMD2<Double>]]) -> [[PolyVert]] {
        var next = 0
        return polygons.map { polygon in
            polygon.map { position in
                defer { next += 1 }
                return PolyVert(pos: position, idx: next)
            }
        }
    }

    /// Manifold's TestPoly: as-is, turned 180 degrees, and duplicated side by side.
    private func check(_ entry: CorpusEntry) {
        let basic = triangulate(indexed(entry.polygons), epsilon: entry.epsilon)
        #expect(basic.count == entry.expectedTriangles, "Basic")

        let turned = entry.polygons.map { $0.map { -$0 } }
        #expect(triangulate(indexed(turned), epsilon: entry.epsilon).count == entry.expectedTriangles, "Turn 180")

        let xs = entry.polygons.flatMap { $0.map(\.x) }
        let shift = (xs.max() ?? 0) - (xs.min() ?? 0)
        let duplicated = entry.polygons + entry.polygons.map { $0.map { $0 + SIMD2(shift, 0) } }
        #expect(triangulate(indexed(duplicated), epsilon: entry.epsilon).count == 2 * entry.expectedTriangles, "Duplicate")
    }

    @Test("Manifold polygon corpus", arguments: mainCorpus)
    func mainCorpusEntry(entry: CorpusEntry) {
        check(entry)
    }

    @Test("Manifold sponge corpus", arguments: spongeCorpus)
    func spongeCorpusEntry(entry: CorpusEntry) {
        check(entry)
    }

    @Test("Corpora loaded")
    func corporaLoaded() {
        #expect(Self.mainCorpus.count == 100)
        #expect(!Self.spongeCorpus.isEmpty)
    }

    @Test("Concave polygon with a hole: area and orientation are exact")
    func holeArea() {
        // An L-shaped outer contour (CCW) with a square hole (CW).
        let outer: [SIMD2<Double>] = [[0, 0], [4, 0], [4, 2], [2, 2], [2, 4], [0, 4]]
        let hole: [SIMD2<Double>] = [[0.5, 0.5], [0.5, 1.5], [1.5, 1.5], [1.5, 0.5]]
        let polys = indexed([outer, hole])
        let positions = polys.flatMap { $0 }.map(\.pos)
        let triangles = triangulate(polys, epsilon: -1)
        #expect(triangles.count == outer.count + hole.count) // V + 2H - 2 with one hole
        var area = 0.0
        for triangle in triangles {
            let a = positions[triangle.x], b = positions[triangle.y], c = positions[triangle.z]
            let twice = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
            #expect(twice > 0)
            area += twice / 2
        }
        #expect(abs(area - (12 - 1)) < 1e-12)
    }

    @Test("Star polygons triangulate fully", arguments: [10, 50, 200])
    func star(points: Int) {
        let polygon = (0..<points).map { i -> SIMD2<Double> in
            let angle = 2 * Double.pi * Double(i) / Double(points)
            let radius = i.isMultiple(of: 2) ? 2.0 : 1.0
            return SIMD2(radius * cos(angle), radius * sin(angle))
        }
        #expect(triangulate(indexed([polygon]), epsilon: -1).count == points - 2)
    }

    @Test("Convex fast path alternates instead of fanning")
    func convex() {
        let octagon = (0..<8).map { i -> SIMD2<Double> in
            let angle = 2 * Double.pi * Double(i) / 8
            return SIMD2(cos(angle), sin(angle))
        }
        let triangles = triangulate(indexed([octagon]), epsilon: -1)
        #expect(triangles.count == 6)
        // No vertex is in every triangle (that would be a fan).
        #expect((0..<8).allSatisfy { v in !triangles.allSatisfy { [$0.x, $0.y, $0.z].contains(v) } })
    }
}
