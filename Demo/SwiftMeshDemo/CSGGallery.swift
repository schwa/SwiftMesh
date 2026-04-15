import SwiftMesh
import SwiftUI

/// A gallery showing CSG (Boolean / Constructive Solid Geometry) operations.
struct CSGGallery: View {
    @State private var selectedExample: CSGExample?

    var body: some View {
        ZStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250))], spacing: 20) {
                    ForEach(CSGExample.all) { example in
                        MeshGridCell(name: example.name, mesh: example.mesh, subtitle: example.subtitle) {
                            withAnimation { selectedExample = example }
                        }
                    }
                }
                .padding()
            }

            if let example = selectedExample {
                MeshDetailView(name: example.name, mesh: example.mesh) {
                    withAnimation { selectedExample = nil }
                }
                .padding(40)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

// MARK: - Examples

private struct CSGExample: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let mesh: Mesh
    let color: Color

    init(_ name: String, subtitle: String, color: Color, mesh: @autoclosure () -> Mesh) {
        self.id = name
        self.name = name
        self.subtitle = subtitle
        self.color = color
        self.mesh = mesh()
    }

    static let all: [CSGExample] = {
        let cubeA = Mesh.box(extents: [0.6, 0.6, 0.6], attributes: [])
        let cubeB = shiftedBox(offset: [0.3, 0.3, 0.3])
        let sphere = Mesh.icoSphere(extents: [0.8, 0.8, 0.8], subdivisions: 2, attributes: [])
        let smallCube = Mesh.box(extents: [0.5, 0.5, 0.5], attributes: [])

        return [
            // Cube + Cube
            CSGExample("Union: Cubes", subtitle: "Two overlapping cubes", color: .blue,
                       mesh: cubeA.union(cubeB)),
            CSGExample("Intersection: Cubes", subtitle: "Overlap region only", color: .green,
                       mesh: cubeA.intersection(cubeB)),
            CSGExample("Difference: Cubes", subtitle: "First minus second", color: .red,
                       mesh: cubeA.difference(cubeB)),

            // Sphere + Cube
            CSGExample("Union: Sphere + Cube", subtitle: "Merged shapes", color: .purple,
                       mesh: sphere.union(smallCube)),
            CSGExample("Intersection: Sphere ∩ Cube", subtitle: "Rounded cube", color: .orange,
                       mesh: sphere.intersection(smallCube)),
            CSGExample("Difference: Sphere − Cube", subtitle: "Cube carved from sphere", color: .cyan,
                       mesh: sphere.difference(smallCube)),

            // Multi-step: Swiss cheese
            CSGExample("Difference: Cube − Sphere", subtitle: "Sphere carved from cube", color: .mint,
                       mesh: smallCube.difference(
                        Mesh.icoSphere(extents: [0.45, 0.45, 0.45], subdivisions: 2, attributes: [])
                       )),
        ]
    }()

    private static func shiftedBox(offset: SIMD3<Float>) -> Mesh {
        var positions = Mesh.box(extents: [0.6, 0.6, 0.6], attributes: []).positions
        for i in positions.indices {
            positions[i] += offset
        }
        return Mesh(positions: positions, faces: [
            [0, 1, 2, 3], [5, 4, 7, 6],
            [4, 0, 3, 7], [1, 5, 6, 2],
            [3, 2, 6, 7], [4, 5, 1, 0]
        ])
    }
}

#Preview {
    CSGGallery()
}
