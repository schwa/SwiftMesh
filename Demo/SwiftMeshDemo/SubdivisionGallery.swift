import SwiftMesh
import SwiftUI

/// A gallery showing subdivision surface results.
struct SubdivisionGallery: View {
    @State private var selectedExample: SubdivisionExample?

    var body: some View {
        ZStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250))], spacing: 20) {
                    ForEach(SubdivisionExample.all) { example in
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

private struct SubdivisionExample: Identifiable {
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

    static let all: [SubdivisionExample] = {
        [
            // Loop subdivision (triangle meshes)
            SubdivisionExample("Tetrahedron", subtitle: "Original (4 faces)", color: .red,
                               mesh: .tetrahedron(attributes: [])),
            SubdivisionExample("Loop ×1", subtitle: "16 faces", color: .red,
                               mesh: Mesh.tetrahedron(attributes: []).loopSubdivided(iterations: 1)),
            SubdivisionExample("Loop ×2", subtitle: "64 faces", color: .red,
                               mesh: Mesh.tetrahedron(attributes: []).loopSubdivided(iterations: 2)),
            SubdivisionExample("Loop ×3", subtitle: "256 faces", color: .red,
                               mesh: Mesh.tetrahedron(attributes: []).loopSubdivided(iterations: 3)),

            // Catmull-Clark subdivision (quad meshes)
            SubdivisionExample("Cube", subtitle: "Original (6 faces)", color: .blue,
                               mesh: .cube(attributes: [])),
            SubdivisionExample("CC ×1", subtitle: "24 faces", color: .blue,
                               mesh: Mesh.cube(attributes: []).catmullClarkSubdivided(iterations: 1)),
            SubdivisionExample("CC ×2", subtitle: "96 faces", color: .blue,
                               mesh: Mesh.cube(attributes: []).catmullClarkSubdivided(iterations: 2)),
            SubdivisionExample("CC ×3", subtitle: "384 faces", color: .blue,
                               mesh: Mesh.cube(attributes: []).catmullClarkSubdivided(iterations: 3)),

            // Catmull-Clark on n-gons
            SubdivisionExample("Dodecahedron", subtitle: "Original (12 pentagons)", color: .purple,
                               mesh: .dodecahedron(attributes: [])),
            SubdivisionExample("CC Dodecahedron ×2", subtitle: "240 quads", color: .purple,
                               mesh: Mesh.dodecahedron(attributes: []).catmullClarkSubdivided(iterations: 2)),

            // Loop on icosahedron
            SubdivisionExample("Icosahedron", subtitle: "Original (20 faces)", color: .orange,
                               mesh: .icosahedron(attributes: [])),
            SubdivisionExample("Loop Icosahedron ×2", subtitle: "320 faces", color: .orange,
                               mesh: Mesh.icosahedron(attributes: []).loopSubdivided(iterations: 2)),
        ]
    }()
}

#Preview {
    SubdivisionGallery()
}
