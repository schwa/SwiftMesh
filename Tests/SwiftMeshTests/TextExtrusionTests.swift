import CoreText
import simd
@testable import SwiftMesh
import Testing

@Suite("Text extrusion")
struct TextExtrusionTests {
    @Test("Glyphs become closed solids with the right genus")
    func hio() {
        let mesh = Mesh.extrudedText("Hio", fontName: "Helvetica", size: 1, depth: 0.2, attributes: [])
        #expect(mesh.validate().isEmpty)
        #expect(mesh.isManifold)
        let components = mesh.topology.surfaceComponents()
        // H, the stem and dot of i, and o.
        #expect(components.count == 4)
        #expect(components.compactMap(\.genus).sorted() == [0, 0, 0, 1])
    }

    @Test("Text is upright, starts at the origin, and spans the depth")
    func orientation() {
        let mesh = Mesh.extrudedText("T", size: 10, depth: 2, attributes: [])
        let (low, high) = (mesh.bounds!.min, mesh.bounds!.max)
        #expect(low.z == 0)
        #expect(high.z == 2)
        #expect(low.y > -0.5) // baseline at y = 0, T has no descender
        let height = high.y - low.y
        func width(_ predicate: (Float) -> Bool) -> Float {
            let xs = mesh.positions.filter { predicate($0.y) }.map(\.x)
            return (xs.max() ?? 0) - (xs.min() ?? 0)
        }
        // The crossbar is at the top, so the top is wider than the bottom.
        #expect(width { $0 > high.y - height * 0.1 } > width { $0 < low.y + height * 0.1 } * 2)
    }

    @Test("Empty and whitespace strings give empty meshes")
    func empty() {
        #expect(Mesh.extrudedText("", depth: 1, attributes: []).faceCount == 0)
        #expect(Mesh.extrudedText("   ", depth: 1, attributes: []).faceCount == 0)
    }
}
