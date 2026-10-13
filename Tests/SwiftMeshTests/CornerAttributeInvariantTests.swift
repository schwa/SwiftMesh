import simd
@testable import SwiftMesh
import Testing

/// Boundary tests: every attribute-preserving operation keeps all corner attributes, sized to the
/// result's half-edges, with unit-length direction attributes.
@Suite("Corner attribute invariants")
struct CornerAttributeInvariantTests {
    /// Adds colors and splits faces into two labeled submeshes, alternating.
    static func fullyAttributed(_ mesh: Mesh) -> Mesh {
        var mesh = mesh
        mesh.colors = mesh.topology.halfEdges.map { SIMD4(mesh.positions[$0.origin.raw] + 0.5, 1) }
        let faces = mesh.topology.faces.map(\.id)
        mesh.submeshes = [
            .init(label: "even", faces: faces.filter { $0.raw.isMultiple(of: 2) }),
            .init(label: "odd", faces: faces.filter { !$0.raw.isMultiple(of: 2) })
        ]
        return mesh
    }

    static let cube = fullyAttributed(.cube(attributes: .all))
    static let openBox: Mesh = {
        let kept = cube.topology.faces.dropFirst().map(\.id)
        let faces = kept.map { cube.topology.vertexLoop(for: $0).map(\.raw) }
        var open = Mesh(positions: cube.positions, faces: faces)
        open.cornerAttributes = cube.cornerAttributes.gathered(kept.flatMap { cube.topology.rebuildCornerOrder(for: $0).map(\.raw) })
        return fullyAttributed(open)
    }()

    static func run(_ operation: String) -> Mesh {
        switch operation {
        case "splitEdge":
            var mesh = cube.triangulated()
            _ = mesh.splitEdge(.init(raw: 0), at: 0.3)
            return mesh

        case "flipEdge":
            var mesh = cube.welded().triangulated()
            let flipped = mesh.topology.halfEdges.map(\.id).contains { mesh.flipEdge($0) }
            #expect(flipped)
            return mesh

        case "extrudingFace": return cube.extrudingFace(.init(raw: 0), distance: 0.5)
        case "fillingHoles": return openBox.fillingHoles()
        case "decimated": return fullyAttributed(.icoSphere(attributes: .all)).decimated(ratio: 0.5)
        case "reversingWinding": return cube.reversingWinding()
        case "triangulated": return cube.triangulated()
        case "welded": return cube.welded()
        case "merged": return Mesh.merged([cube, cube.translated(by: [3, 0, 0])])
        case "union": return cube.union(cube.translated(by: [0.5, 0.5, 0.5]))
        case "difference": return cube.difference(cube.translated(by: [0.5, 0.5, 0.5]))
        default: fatalError("unknown operation \(operation)")
        }
    }

    @Test("operations keep every corner attribute", arguments: [
        "splitEdge", "flipEdge", "extrudingFace", "fillingHoles", "decimated", "reversingWinding",
        "triangulated", "welded", "merged", "union", "difference"
    ])
    func keepsAttributes(operation: String) {
        let mesh = Self.run(operation)
        let corners = mesh.topology.halfEdges.count
        #expect(corners > 0)
        #expect(mesh.normals?.count == corners)
        #expect(mesh.textureCoordinates?.count == corners)
        #expect(mesh.tangents?.count == corners)
        #expect(mesh.bitangents?.count == corners)
        #expect(mesh.colors?.count == corners)
        for direction in [mesh.normals, mesh.tangents, mesh.bitangents] {
            for value in direction ?? [] {
                #expect(abs(simd_length(value) - 1) < 1e-3)
            }
        }
    }

    @Test("operations keep every face in exactly one labeled submesh", arguments: [
        "splitEdge", "flipEdge", "extrudingFace", "fillingHoles", "decimated", "reversingWinding",
        "triangulated", "welded", "merged"
    ])
    func keepsSubmeshes(operation: String) {
        let mesh = Self.run(operation)
        let labels = mesh.submeshes.map(\.label)
        #expect(Set(labels) == ["even", "odd"])
        let assigned = mesh.submeshes.flatMap(\.faces).map(\.raw).sorted()
        #expect(assigned == Array(0..<mesh.topology.faces.count))
    }
}
