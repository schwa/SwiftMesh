import Metal
import MetalKit
import ModelIO
import simd
import SwiftMesh
import SwiftMeshIO
import SwiftUI
import UniformTypeIdentifiers

enum SidebarSelection: Hashable {
    case all
    case item(MeshGalleryItem)
}

struct ContentView: View {
    @State private var selection: SidebarSelection? = .all
    @State private var importedItems: [MeshGalleryItem] = []
    @State private var importError: String?
    @AppStorage("useMetalRenderer") private var useMetalRenderer = false
    @AppStorage("animateRotation") private var animateRotation = true
    @State private var renderMode: MeshRenderMode = .blinnPhong

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                NavigationLink(value: SidebarSelection.all) {
                    Label("All", systemImage: "square.grid.2x2")
                }
                if !importedItems.isEmpty {
                    Section("Imported") {
                        ForEach(importedItems) { item in
                            NavigationLink(value: SidebarSelection.item(item)) {
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
                ForEach(MeshGallerySection.all) { section in
                    Section(section.name) {
                        ForEach(section.items) { item in
                            NavigationLink(value: SidebarSelection.item(item)) {
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
            switch selection {
            case .all:
                GalleryGridView(selection: $selection)

            case .item(let item):
                MeshDetailView(item: item, useMetalRenderer: useMetalRenderer, animateRotation: animateRotation, renderMode: renderMode)
                    .id(item.id)

            case nil:
                ContentUnavailableView("Select a Mesh", systemImage: "square.grid.2x2", description: Text("Choose a mesh from the sidebar"))
            }
        }
        .toolbar {
            Toggle(isOn: $useMetalRenderer) {
                Label("Metal", systemImage: "cube")
            }
            if useMetalRenderer {
                Picker("Mode", selection: $renderMode) {
                    Text("Blinn-Phong").tag(MeshRenderMode.blinnPhong)
                    Divider()
                    ForEach(MeshDebugMode.allCases) { mode in
                        Text(mode.label).tag(MeshRenderMode.debug(mode))
                    }
                }
                .pickerStyle(.menu)
                Toggle(isOn: $animateRotation) {
                    Label("Animate", systemImage: "play")
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls {
                importMesh(from: url)
            }
            return !urls.isEmpty
        }
        .alert("Import Error", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private func importMesh(from url: URL) {
        do {
            let mesh = try Self.loadMesh(from: url)
            let name = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension.uppercased()
            let item = MeshGalleryItem("\(name) (\(ext))", subtitle: "Imported", mesh: mesh)
            importedItems.append(item)
            selection = .item(item)
        } catch {
            importError = error.localizedDescription
        }
    }

    private static func loadMesh(from url: URL) throws -> Mesh {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MeshImportError.noMetalDevice
        }
        let allocator = MTKMeshBufferAllocator(device: device)
        let asset = MDLAsset(url: url, vertexDescriptor: nil, bufferAllocator: allocator)
        guard let mdlMesh = asset.childObjects(of: MDLMesh.self).first as? MDLMesh else {
            throw MeshImportError.noMeshFound(url.lastPathComponent)
        }
        var mesh = try Mesh(mdlMesh: mdlMesh, device: device)
        mesh.normals = nil
        mesh.textureCoordinates = nil
        mesh.tangents = nil
        mesh.bitangents = nil
        mesh.colors = nil
        return mesh
    }
}

enum MeshImportError: Error, LocalizedError {
    case noMetalDevice
    case noMeshFound(String)

    var errorDescription: String? {
        switch self {
        case .noMetalDevice:
            "No Metal device available"

        case .noMeshFound(let filename):
            "No mesh found in \(filename)"
        }
    }
}

// MARK: - Gallery Grid

struct GalleryGridView: View {
    @Binding var selection: SidebarSelection?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 20) {
                ForEach(MeshGallerySection.all) { section in
                    Section {
                        ForEach(section.items) { item in
                            Button {
                                selection = .item(item)
                            } label: {
                                VStack {
                                    MeshPreviewView(mesh: item.mesh)
                                        .frame(height: 200)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text(item.name)
                                        .font(.headline)
                                    if let subtitle = item.subtitle {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
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
        .navigationTitle("All Meshes")
    }
}

// MARK: - Detail View

struct MeshDetailView: View {
    let item: MeshGalleryItem
    var useMetalRenderer: Bool
    var animateRotation: Bool
    var renderMode: MeshRenderMode

    @State private var currentMesh: Mesh
    @State private var showStandalone = true
    @State private var standaloneFaceIDs: Set<HalfEdgeTopology.FaceID>?
    @State private var showInspector = true
    @State private var selection: MeshSelection?
    @State private var showVertexDots = false
    @State private var isModified = false
    @State private var isExporting = false

    init(item: MeshGalleryItem, useMetalRenderer: Bool = false, animateRotation: Bool = true, renderMode: MeshRenderMode = .blinnPhong) {
        self.item = item
        self.useMetalRenderer = useMetalRenderer
        self.animateRotation = animateRotation
        self.renderMode = renderMode
        self._currentMesh = State(initialValue: item.mesh)
    }

    var body: some View {
        Group {
            if useMetalRenderer {
                MetalMeshView(mesh: currentMesh, animating: animateRotation, renderMode: renderMode)
            } else {
                MeshInteractiveView(
                    mesh: currentMesh,
                    highlightedFaces: showStandalone ? standaloneFaceIDs : nil,
                    showVertexDots: showVertexDots,
                    selection: $selection
                )
            }
        }
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
                    LabeledContent("Standalone Faces", value: "\(standaloneFaceIDs?.count ?? 0)")
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
                    Button("Weld") {
                        applyOperation { $0.welded(tolerance: 1e-4) }
                    }
                    Button("Triangulate") {
                        applyOperation { $0.triangulated() }
                    }
                    Button("Subdivide (Loop)") {
                        applyOperation { $0.loopSubdivided(iterations: 1) }
                    }
                    Button("Subdivide (CC)") {
                        applyOperation { $0.catmullClarkSubdivided(iterations: 1) }
                    }
                    Button("Decimate 50%") {
                        applyOperation { $0.decimated(ratio: 0.5) }
                    }
                    Button("Wireframe") {
                        applyOperation { $0.wireframe(radius: 0.015, sides: 8) }
                    }

                    Toggle("Highlight Standalone", isOn: $showStandalone)
                    Toggle("Vertex Dots", isOn: $showVertexDots)

                    if isModified {
                        Button("Reset") {
                            currentMesh = item.mesh
                            isModified = false
                            recomputeStandalone()
                        }
                    }
                }
            }
            .inspectorColumnWidth(min: 220, ideal: 260, max: 320)
        }
        .toolbar {
            Button {
                isExporting = true
            } label: {
                Label("Export PLY", systemImage: "square.and.arrow.up")
            }
            Toggle(isOn: $showInspector) {
                Label("Inspector", systemImage: "sidebar.right")
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: PLYDocument(mesh: currentMesh),
            contentType: .ply,
            defaultFilename: "\(item.name).ply"
        ) { _ in }
        .onAppear { recomputeStandalone() }
    }

    private func applyOperation(_ operation: (Mesh) -> Mesh) {
        currentMesh = operation(currentMesh)
        isModified = true
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

    static let all: [Self] = [
        Self("Platonic Solids", items: [
            MeshGalleryItem("Tetrahedron", mesh: .tetrahedron()),
            MeshGalleryItem("Cube", mesh: .cube()),
            MeshGalleryItem("Octahedron", mesh: .octahedron()),
            MeshGalleryItem("Icosahedron", mesh: .icosahedron()),
            MeshGalleryItem("Dodecahedron", mesh: .dodecahedron())
        ]),
        Self("Surfaces", items: [
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
            MeshGalleryItem("CubeSphere", mesh: .cubeSphere())
        ]),
        Self("CSG", items: {
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
                ))
            ]
        }()),
        Self("Subdivision", items: [
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
            MeshGalleryItem("Loop Icosahedron ×2", subtitle: "320 faces", mesh: Mesh.icosahedron(attributes: []).loopSubdivided(iterations: 2))
        ]),
        Self("Marching Cubes", items: {
            let bounds: (min: SIMD3<Float>, max: SIMD3<Float>) = (SIMD3(-0.5, -0.5, -0.5), SIMD3(0.5, 0.5, 0.5))
            return [
                MeshGalleryItem("MC Sphere", subtitle: "SDF sphere", mesh: .marchingCubes(resolution: 32, bounds: bounds) { p in
                    simd_length(p) - 0.4
                }),
                MeshGalleryItem("MC Torus", subtitle: "SDF torus", mesh: .marchingCubes(resolution: 32, bounds: bounds) { p in
                    let q = SIMD2<Float>(simd_length(SIMD2<Float>(p.x, p.z)) - 0.3, p.y)
                    return simd_length(q) - 0.1
                }),
                MeshGalleryItem("MC Rounded Box", subtitle: "SDF rounded box", mesh: .marchingCubes(resolution: 32, bounds: bounds) { p in
                    let q = SIMD3<Float>(abs(p.x), abs(p.y), abs(p.z)) - SIMD3<Float>(0.25, 0.25, 0.25)
                    let outside = simd_length(SIMD3<Float>(max(q.x, 0), max(q.y, 0), max(q.z, 0)))
                    let inside = min(max(q.x, max(q.y, q.z)), Float(0))
                    return outside + inside - 0.05
                }),
                MeshGalleryItem("MC Gyroid", subtitle: "Triply periodic surface", mesh: .marchingCubes(resolution: 24, bounds: bounds) { p in
                    let s = p * (2 * .pi * 3)
                    let g = sin(s.x) * cos(s.y) + sin(s.y) * cos(s.z) + sin(s.z) * cos(s.x)
                    return abs(g) - 0.3
                })
            ]
        }()),
        Self("Convex Hull", items: {
            // Random point cloud
            var randomPoints: [SIMD3<Float>] = []
            var seed: UInt32 = 12_345
            for _ in 0..<80 {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let x = Float(seed % 1_000) / 500.0 - 1.0
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let y = Float(seed % 1_000) / 500.0 - 1.0
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let z = Float(seed % 1_000) / 500.0 - 1.0
                randomPoints.append(SIMD3(x, y, z) * 0.4)
            }

            // Points on a sphere (golden spiral)
            var spherePoints: [SIMD3<Float>] = []
            let n = 40
            let phi: Float = (1 + sqrt(5)) / 2
            for i in 0..<n {
                let theta = acos(1 - 2 * (Float(i) + 0.5) / Float(n))
                let angle = 2 * Float.pi * Float(i) / phi
                spherePoints.append(SIMD3(sin(theta) * cos(angle), sin(theta) * sin(angle), cos(theta)) * 0.4)
            }

            // Cube corners + noisy interior
            var noisyCubePoints: [SIMD3<Float>] = [
                SIMD3(-1, -1, -1), SIMD3(1, -1, -1), SIMD3(1, 1, -1), SIMD3(-1, 1, -1),
                SIMD3(-1, -1, 1), SIMD3(1, -1, 1), SIMD3(1, 1, 1), SIMD3(-1, 1, 1)
            ].map { $0 * 0.4 }
            for _ in 0..<30 {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let x = Float(seed % 1_000) / 500.0 - 1.0
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let y = Float(seed % 1_000) / 500.0 - 1.0
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let z = Float(seed % 1_000) / 500.0 - 1.0
                noisyCubePoints.append(SIMD3(x, y, z) * 0.3)
            }

            return [
                MeshGalleryItem("Random Cloud", subtitle: "80 random points",
                    mesh: Mesh.convexHull(of: randomPoints, attributes: []) ?? .tetrahedron(attributes: [])),
                MeshGalleryItem("Sphere Points", subtitle: "40 points on sphere",
                    mesh: Mesh.convexHull(of: spherePoints, attributes: []) ?? .tetrahedron(attributes: [])),
                MeshGalleryItem("Noisy Cube", subtitle: "Cube corners + 30 interior",
                    mesh: Mesh.convexHull(of: noisyCubePoints, attributes: []) ?? .tetrahedron(attributes: []))
            ]
        }()),
        Self("Wireframe", items: {
            let cube = Mesh.cube(attributes: [])
            let icosahedron = Mesh.icosahedron(attributes: [])
            let dodecahedron = Mesh.dodecahedron(attributes: [])
            let torus = Mesh.torus(majorSegments: 16, minorSegments: 8, attributes: [])
            return [
                MeshGalleryItem("Cube Wireframe", subtitle: "Rectangular tubes",
                    mesh: cube.wireframe(radius: 0.02, sides: 4)),
                MeshGalleryItem("Cube Wireframe (Cyl)", subtitle: "Cylindrical tubes",
                    mesh: cube.wireframe(radius: 0.02, sides: 16)),
                MeshGalleryItem("Icosahedron Wireframe", subtitle: "20-face polyhedron",
                    mesh: icosahedron.wireframe(radius: 0.015, sides: 8)),
                MeshGalleryItem("Dodecahedron Wireframe", subtitle: "12 pentagons",
                    mesh: dodecahedron.wireframe(radius: 0.015, sides: 8)),
                MeshGalleryItem("Torus Wireframe", subtitle: "16×8 torus grid",
                    mesh: torus.wireframe(radius: 0.005, sides: 6)),
                MeshGalleryItem("Phat Cube", subtitle: "Thicc boi",
                    mesh: cube.wireframe(radius: 0.06, sides: 12))
            ]
        }()),
        Self("Decimation", items: {
            let sphere = Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 3, attributes: [])
            let sphereFaces = sphere.topology.faces.filter { $0.edge != nil }.count
            return [
                MeshGalleryItem("IcoSphere", subtitle: "Original (\(sphereFaces) faces)", mesh: sphere),
                MeshGalleryItem("50%", subtitle: "\(sphereFaces / 2) faces", mesh: sphere.decimated(ratio: 0.5)),
                MeshGalleryItem("25%", subtitle: "\(sphereFaces / 4) faces", mesh: sphere.decimated(ratio: 0.25)),
                MeshGalleryItem("10%", subtitle: "\(sphereFaces / 10) faces", mesh: sphere.decimated(ratio: 0.1))
            ]
        }())
    ]
}

// MARK: - PLY Export

struct PLYDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.ply] }

    let data: Data

    init(mesh: Mesh) {
        self.data = PLY.write(mesh)
    }

    init(configuration: ReadConfiguration) {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration _: WriteConfiguration) -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension UTType {
    static let ply = UTType(filenameExtension: "ply") ?? .data
}

#Preview {
    ContentView()
}
