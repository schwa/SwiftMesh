import SwiftMesh
import SwiftUI

struct ContentView: View {
    @State private var selectedItem: MeshGalleryItem?

    var body: some View {
        ZStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250))], spacing: 20) {
                    ForEach(MeshGallerySection.all) { section in
                        Section {
                            ForEach(section.items) { item in
                                MeshGridCell(name: item.name, mesh: item.mesh, subtitle: item.subtitle) {
                                    withAnimation { selectedItem = item }
                                }
                            }
                        } header: {
                            Text(section.name)
                                .font(.title2.bold())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 10)
                        }
                    }
                }
                .padding()
            }

            if let item = selectedItem {
                MeshDetailView(name: item.name, mesh: item.mesh) {
                    withAnimation { selectedItem = nil }
                }
                .padding(40)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

// MARK: - Data

struct MeshGalleryItem: Identifiable {
    let id: String
    let name: String
    let subtitle: String?
    let mesh: Mesh

    init(_ name: String, subtitle: String? = nil, mesh: @autoclosure () -> Mesh) {
        self.id = name
        self.name = name
        self.subtitle = subtitle
        self.mesh = mesh()
    }
}

private struct MeshGallerySection: Identifiable {
    let id: String
    let name: String
    let items: [MeshGalleryItem]

    init(_ name: String, items: [MeshGalleryItem]) {
        self.id = name
        self.name = name
        self.items = items
    }

    static let all: [MeshGallerySection] = [
        MeshGallerySection("Platonic Solids", items: [
            MeshGalleryItem("Tetrahedron", mesh: .tetrahedron()),
            MeshGalleryItem("Cube", mesh: .cube()),
            MeshGalleryItem("Octahedron", mesh: .octahedron()),
            MeshGalleryItem("Icosahedron", mesh: .icosahedron()),
            MeshGalleryItem("Dodecahedron", mesh: .dodecahedron()),
        ]),
        MeshGallerySection("Surfaces", items: [
            MeshGalleryItem("Sphere", mesh: .sphere()),
            MeshGalleryItem("Torus", mesh: .torus()),
            MeshGalleryItem("Cylinder", mesh: .cylinder()),
            MeshGalleryItem("Cone", mesh: .cone()),
            MeshGalleryItem("Box", mesh: .box()),
            MeshGalleryItem("Hemisphere", mesh: .hemisphere()),
            MeshGalleryItem("Capsule", mesh: .capsule()),
            MeshGalleryItem("Conical Frustum", mesh: .conicalFrustum()),
            MeshGalleryItem("Rect Frustum", mesh: .rectangularFrustum()),
            MeshGalleryItem("Circle", mesh: .circle()),
            MeshGalleryItem("Teapot", mesh: .teapot()),
            MeshGalleryItem("IcoSphere", mesh: .icoSphere()),
            MeshGalleryItem("CubeSphere", mesh: .cubeSphere()),
        ]),
        MeshGallerySection("CSG", items: {
            let cubeA = Mesh.box(extents: [0.6, 0.6, 0.6], attributes: [])
            let cubeB: Mesh = {
                var positions = Mesh.box(extents: [0.6, 0.6, 0.6], attributes: []).positions
                for i in positions.indices { positions[i] += [0.3, 0.3, 0.3] }
                return Mesh(positions: positions, faces: [
                    [0, 1, 2, 3], [5, 4, 7, 6],
                    [4, 0, 3, 7], [1, 5, 6, 2],
                    [3, 2, 6, 7], [4, 5, 1, 0]
                ])
            }()
            let sphere = Mesh.icoSphere(extents: [0.8, 0.8, 0.8], subdivisions: 2, attributes: [])
            let smallCube = Mesh.box(extents: [0.5, 0.5, 0.5], attributes: [])
            return [
                MeshGalleryItem("Union: Cubes", subtitle: "Two overlapping cubes", mesh: cubeA.union(cubeB)),
                MeshGalleryItem("Intersection: Cubes", subtitle: "Overlap region only", mesh: cubeA.intersection(cubeB)),
                MeshGalleryItem("Difference: Cubes", subtitle: "First minus second", mesh: cubeA.difference(cubeB)),
                MeshGalleryItem("Union: Sphere + Cube", subtitle: "Merged shapes", mesh: sphere.union(smallCube)),
                MeshGalleryItem("Intersection: Sphere ∩ Cube", subtitle: "Rounded cube", mesh: sphere.intersection(smallCube)),
                MeshGalleryItem("Difference: Sphere − Cube", subtitle: "Cube carved from sphere", mesh: sphere.difference(smallCube)),
                MeshGalleryItem("Difference: Cube − Sphere", subtitle: "Sphere carved from cube", mesh: smallCube.difference(
                    Mesh.icoSphere(extents: [0.45, 0.45, 0.45], subdivisions: 2, attributes: [])
                )),
            ]
        }()),
        MeshGallerySection("Subdivision", items: [
            MeshGalleryItem("Tetrahedron", subtitle: "Original (4 faces)", mesh: .tetrahedron(attributes: [])),
            MeshGalleryItem("Loop ×1", subtitle: "16 faces", mesh: Mesh.tetrahedron(attributes: []).loopSubdivided(iterations: 1)),
            MeshGalleryItem("Loop ×2", subtitle: "64 faces", mesh: Mesh.tetrahedron(attributes: []).loopSubdivided(iterations: 2)),
            MeshGalleryItem("Loop ×3", subtitle: "256 faces", mesh: Mesh.tetrahedron(attributes: []).loopSubdivided(iterations: 3)),
            MeshGalleryItem("Cube", subtitle: "Original (6 faces)", mesh: .cube(attributes: [])),
            MeshGalleryItem("CC ×1", subtitle: "24 faces", mesh: Mesh.cube(attributes: []).catmullClarkSubdivided(iterations: 1)),
            MeshGalleryItem("CC ×2", subtitle: "96 faces", mesh: Mesh.cube(attributes: []).catmullClarkSubdivided(iterations: 2)),
            MeshGalleryItem("CC ×3", subtitle: "384 faces", mesh: Mesh.cube(attributes: []).catmullClarkSubdivided(iterations: 3)),
            MeshGalleryItem("Dodecahedron", subtitle: "Original (12 pentagons)", mesh: .dodecahedron(attributes: [])),
            MeshGalleryItem("CC Dodecahedron ×2", subtitle: "240 quads", mesh: Mesh.dodecahedron(attributes: []).catmullClarkSubdivided(iterations: 2)),
            MeshGalleryItem("Icosahedron", subtitle: "Original (20 faces)", mesh: .icosahedron(attributes: [])),
            MeshGalleryItem("Loop Icosahedron ×2", subtitle: "320 faces", mesh: Mesh.icosahedron(attributes: []).loopSubdivided(iterations: 2)),
        ]),
    ]
}

#Preview {
    ContentView()
}
