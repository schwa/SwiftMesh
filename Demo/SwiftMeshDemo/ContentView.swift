import simd
import SwiftMesh
import SwiftUI

struct ContentView: View {
    @State private var selectedItem: MeshGalleryItem?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                ForEach(MeshGallerySection.all) { section in
                    Section(section.name) {
                        ForEach(section.items) { item in
                            NavigationLink(value: item) {
                                HStack {
                                    MeshPreviewView(mesh: item.mesh)
                                        .frame(width: 48, height: 48)
                                    VStack(alignment: .leading) {
                                        Text(item.name)
                                        if let subtitle = item.subtitle {
                                            Text(subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("SwiftMesh")
            .listStyle(.sidebar)
        } detail: {
            if let item = selectedItem {
                MeshDetailView(item: item)
                    .id(item.id)
            } else {
                ContentUnavailableView("Select a Mesh", systemImage: "square.grid.2x2", description: Text("Choose a mesh from the sidebar"))
            }
        }
    }
}

// MARK: - Detail View

struct MeshDetailView: View {
    let item: MeshGalleryItem

    @State private var displayMesh: Mesh?
    @State private var isTriangulated = false
    @State private var showStandalone = true
    @State private var standaloneFaceIDs: Set<HalfEdgeTopology.FaceID>?
    @State private var decimationRatio: Float = 1.0
    @State private var subdivisionLevel: Int = 0
    @State private var isWelded = false
    @State private var showInspector = true
    @State private var selection: MeshSelection?

    private var mesh: Mesh { item.mesh }

    private var currentMesh: Mesh {
        displayMesh ?? mesh
    }

    var body: some View {
        MeshInteractiveView(
            mesh: currentMesh,
            highlightedFaces: showStandalone ? standaloneFaceIDs : nil,
            selection: $selection
        )
        .navigationTitle(item.name)
        .navigationSubtitle(item.subtitle ?? "")
        .inspector(isPresented: $showInspector) {
            Form {
                Section("Info") {
                    LabeledContent("Vertices", value: "\(currentMesh.vertexCount)")
                    LabeledContent("Faces", value: "\(currentMesh.faceCount)")
                    LabeledContent("Edges", value: "\(currentMesh.edgeCount)")
                    LabeledContent("Half-Edges", value: "\(currentMesh.topology.halfEdges.count)")
                    LabeledContent("Submeshes", value: "\(currentMesh.submeshes.count)")
                    LabeledContent("Manifold") {
                        Text(currentMesh.isManifold ? "Yes" : "No")
                            .foregroundStyle(currentMesh.isManifold ? .green : .red)
                    }
                    if showStandalone, let ids = standaloneFaceIDs {
                        LabeledContent("Standalone Faces", value: "\(ids.count)")
                    }
                }
                if let selection {
                    Section("Selection") {
                        switch selection {
                        case .vertex(let idx):
                            LabeledContent("Type", value: "Vertex")
                            LabeledContent("Index", value: "\(idx)")
                            let pos = currentMesh.positions[idx]
                            LabeledContent("Position", value: String(format: "(%.3f, %.3f, %.3f)", pos.x, pos.y, pos.z))
                            Button("Select Connected Edges") {
                                selectConnectedEdges(vertex: idx)
                            }
                        case .edges(let edges):
                            LabeledContent("Type", value: "Edge\(edges.count == 1 ? "" : "s")")
                            LabeledContent("Count", value: "\(edges.count)")
                            if edges.count == 1, let edge = edges.first {
                                LabeledContent("Vertices", value: "\(edge.a) — \(edge.b)")
                                let length = simd_length(currentMesh.positions[edge.b] - currentMesh.positions[edge.a])
                                LabeledContent("Length", value: String(format: "%.4f", length))
                                Button("Select Face Edges") {
                                    selectFaceEdges(edge: edge)
                                }
                            }
                        }
                        Button("Clear Selection") {
                            self.selection = nil
                        }
                    }
                }
                Section("Attributes") {
                    LabeledContent("Normals", value: currentMesh.normals != nil ? "✓" : "—")
                    LabeledContent("UVs", value: currentMesh.textureCoordinates != nil ? "✓" : "—")
                    LabeledContent("Tangents", value: currentMesh.tangents != nil ? "✓" : "—")
                    LabeledContent("Bitangents", value: currentMesh.bitangents != nil ? "✓" : "—")
                    LabeledContent("Colors", value: currentMesh.colors != nil ? "✓" : "—")
                }
                Section("Operations") {
                    Toggle("Weld", isOn: $isWelded)
                        .onChange(of: isWelded) { rebuildDisplayMesh() }
                    Toggle("Triangulate", isOn: $isTriangulated)
                        .onChange(of: isTriangulated) { rebuildDisplayMesh() }
                    Toggle("Standalone Faces", isOn: $showStandalone)
                        .onChange(of: showStandalone) { if showStandalone { recomputeStandalone() } }

                    HStack {
                        Text("Subdivide")
                        Spacer()
                        Stepper("\(subdivisionLevel)×", value: $subdivisionLevel, in: 0...4)
                            .onChange(of: subdivisionLevel) { rebuildDisplayMesh() }
                    }

                    VStack(alignment: .leading) {
                        Text("Decimate")
                        Slider(value: $decimationRatio, in: 0.05...1.0, step: 0.05)
                            .onChange(of: decimationRatio) { rebuildDisplayMesh() }
                        Text("\(Int(decimationRatio * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if isModified {
                        Button("Reset All") {
                            isWelded = false
                            isTriangulated = false
                            subdivisionLevel = 0
                            decimationRatio = 1.0
                            rebuildDisplayMesh()
                        }
                    }
                }
            }
            .inspectorColumnWidth(min: 220, ideal: 260, max: 320)
        }
        .toolbar {
            Toggle(isOn: $showInspector) {
                Label("Inspector", systemImage: "sidebar.right")
            }
        }
        .onAppear { recomputeStandalone() }
    }

    private var isModified: Bool {
        isWelded || isTriangulated || subdivisionLevel > 0 || decimationRatio < 1.0
    }

    private func rebuildDisplayMesh() {
        var result = mesh
        if isWelded {
            result = result.welded(tolerance: 1e-4)
        }
        if isTriangulated {
            result = result.triangulated()
        }
        if subdivisionLevel > 0 {
            if isTriangulated {
                result = result.loopSubdivided(iterations: subdivisionLevel)
            } else {
                result = result.catmullClarkSubdivided(iterations: subdivisionLevel)
            }
        }
        if decimationRatio < 1.0 {
            result = result.decimated(ratio: decimationRatio)
        }
        displayMesh = isModified ? result : nil
        recomputeStandalone()
    }

    private func recomputeStandalone() {
        standaloneFaceIDs = currentMesh.standaloneFaces()
    }

    private func selectConnectedEdges(vertex idx: Int) {
        var result = Set<MeshEdge>()
        let vid = HalfEdgeTopology.VertexID(raw: idx)
        for he in currentMesh.topology.halfEdges where he.origin == vid {
            if let next = he.next {
                let dest = currentMesh.topology.halfEdges[next.raw].origin
                result.insert(MeshEdge(idx, dest.raw))
            }
        }
        for he in currentMesh.topology.halfEdges {
            if let next = he.next, currentMesh.topology.halfEdges[next.raw].origin == vid {
                result.insert(MeshEdge(he.origin.raw, idx))
            }
        }
        selection = .edges(result)
    }

    private func selectFaceEdges(edge: MeshEdge) {
        var result = Set<MeshEdge>()
        for face in currentMesh.topology.faces {
            let verts = currentMesh.topology.vertexLoop(for: face.id)
            let hasEdge = (0..<verts.count).contains { i in
                let next = (i + 1) % verts.count
                return MeshEdge(verts[i].raw, verts[next].raw) == edge
            }
            if hasEdge {
                for i in 0..<verts.count {
                    let next = (i + 1) % verts.count
                    result.insert(MeshEdge(verts[i].raw, verts[next].raw))
                }
            }
        }
        selection = .edges(result)
    }
}

// MARK: - Data

struct MeshGalleryItem: Identifiable, Hashable {
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

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct MeshGallerySection: Identifiable {
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
            MeshGalleryItem("Quad", mesh: .quad()),
            MeshGalleryItem("Circle", mesh: .circle()),
            MeshGalleryItem("Teapot", mesh: .teapot()),
            MeshGalleryItem("IcoSphere", mesh: .icoSphere()),
            MeshGalleryItem("CubeSphere", mesh: .cubeSphere()),
        ]),
        MeshGallerySection("CSG", items: {
            let cubeA = Mesh.box(extents: [0.6, 0.6, 0.6], attributes: [])
            let cubeB = Mesh.box(extents: [0.6, 0.6, 0.6], attributes: []).translated(by: [0.3, 0.3, 0.3])
            let sphere = Mesh.icoSphere(extents: [0.8, 0.8, 0.8], subdivisions: 2, attributes: [])
            let smallCube = Mesh.box(extents: [0.5, 0.5, 0.5], attributes: []).translated(by: [0.2, 0.2, 0.2])
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
        MeshGallerySection("Decimation", items: {
            let sphere = Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 3, attributes: [])
            let sphereFaces = sphere.topology.faces.filter { $0.edge != nil }.count
            return [
                MeshGalleryItem("IcoSphere", subtitle: "Original (\(sphereFaces) faces)", mesh: sphere),
                MeshGalleryItem("50%", subtitle: "\(sphereFaces / 2) faces", mesh: sphere.decimated(ratio: 0.5)),
                MeshGalleryItem("25%", subtitle: "\(sphereFaces / 4) faces", mesh: sphere.decimated(ratio: 0.25)),
                MeshGalleryItem("10%", subtitle: "\(sphereFaces / 10) faces", mesh: sphere.decimated(ratio: 0.1)),
            ]
        }()),
    ]
}

#Preview {
    ContentView()
}
