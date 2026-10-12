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
                .help("Every gallery mesh in a grid. Drop a mesh file (OBJ, USDZ, PLY, ...) on the window to import it.")
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
                            .help("Imported by drag and drop. Files with several objects load as one mesh with a submesh per object.")
                        }
                    }
                }
                ForEach(MeshGallerySection.all) { section in
                    Section {
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
                            .help(section.help(for: item))
                        }
                    } header: {
                        Text(section.name)
                            .help(section.help)
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
            .help("Render with Metal (lit or debug shaders). Off shows the interactive wireframe view, which supports vertex and edge selection.")
            if useMetalRenderer {
                Picker("Mode", selection: $renderMode) {
                    Text("Blinn-Phong").tag(MeshRenderMode.blinnPhong)
                    Divider()
                    ForEach(MeshDebugMode.allCases) { mode in
                        Text(mode.label).tag(MeshRenderMode.debug(mode))
                    }
                    Divider()
                    ForEach(TopologyOverlay.allCases) { overlay in
                        Text(overlay.label).tag(MeshRenderMode.topology(overlay))
                    }
                }
                .pickerStyle(.menu)
                .help("\(renderMode.label): \(renderMode.helpText)")
                Toggle(isOn: $animateRotation) {
                    Label("Animate", systemImage: "play")
                }
                .help("Slowly rotate the mesh in the Metal view.")
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
        // Every mesh in the asset, placed by its world transform; each becomes a labeled submesh.
        let meshes = try [Mesh](mdlAsset: asset, device: device)
        guard !meshes.isEmpty else {
            throw MeshImportError.noMeshFound(url.lastPathComponent)
        }
        var mesh = Mesh.merged(meshes)
        if meshes.count > 1 {
            for index in mesh.submeshes.indices {
                mesh.submeshes[index].label = mesh.submeshes[index].label ?? "Object \(index + 1)"
            }
        }
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
                            .help(section.help(for: item))
                        }
                    } header: {
                        Text(section.name)
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 10)
                            .help(section.help)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("All Meshes")
    }
}

// MARK: - Diagnostics

/// Topology diagnostics for the inspector, computed once per mesh.
struct MeshDiagnosticsReport {
    var components: [SurfaceComponent]
    var eulerCharacteristic: Int
    var boundaryLoops: Int
    var inconsistentWindingEdges: Int
    var validationErrors: Int
    var validationWarnings: [String]
    var valenceHistogram: [(valence: Int, count: Int)]

    init(mesh: Mesh) {
        let topology = mesh.topology
        components = topology.surfaceComponents()
        eulerCharacteristic = components.reduce(0) { $0 + $1.eulerCharacteristic }
        boundaryLoops = topology.boundaryLoopCount
        inconsistentWindingEdges = topology.inconsistentWindingEdges().count
        let issues = mesh.validate()
        validationErrors = issues.filter { $0.severity == .error }.count
        validationWarnings = issues.filter { $0.severity == .warning }.map(\.message)
        valenceHistogram = topology.valenceHistogram().sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}

struct MeshDiagnosticsSection: View {
    let report: MeshDiagnosticsReport

    var body: some View {
        Section("Diagnostics") {
            LabeledContent("Euler \u{3c7}", value: "\(report.eulerCharacteristic)")
                .help("V - E + F (holed faces count -1 per hole). A closed sphere-like surface has 2; each handle lowers it by 2.")
            LabeledContent("Components", value: "\(report.components.count)")
                .help("Separate pieces: faces connected across shared edges.")
            ForEach(Array(report.components.prefix(6).enumerated()), id: \.offset) { index, component in
                LabeledContent("  #\(index + 1)", value: describe(component))
                    .help("Genus counts handles: 0 = sphere-like, 1 = torus-like. Invalid genus means the piece isn't a proper surface. Non-orientable pieces (like a Mobius strip) have no consistent inside and outside.")
            }
            if report.components.count > 6 {
                LabeledContent("", value: "+\(report.components.count - 6) more")
            }
            LabeledContent("Boundary Loops", value: "\(report.boundaryLoops)")
                .help("Open holes in the surface. 0 means watertight. Use the Boundary Edges render mode to see them.")
            LabeledContent("Bad Winding Edges") {
                Text("\(report.inconsistentWindingEdges)")
                    .foregroundStyle(report.inconsistentWindingEdges == 0 ? .green : .red)
            }
            .help("Edges where two faces run the same direction, meaning one of them is flipped. Fix Winding repairs this when the surface is orientable.")
            LabeledContent("Validation") {
                Text("\(report.validationErrors) errors, \(report.validationWarnings.count) warnings")
                    .foregroundStyle(report.validationErrors > 0 ? .red : report.validationWarnings.isEmpty ? .green : .orange)
            }
            .help("Mesh.validate(): errors are broken wiring or attribute counts; warnings (such as non-manifold edges) are legal but suspicious.")
            ForEach(Array(report.validationWarnings.prefix(3).enumerated()), id: \.offset) { _, warning in
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Valence", value: report.valenceHistogram.map { "\($0.valence):\($0.count)" }.joined(separator: " "))
                .help("Neighbor count per vertex, as valence:vertices. Regular triangle meshes are mostly 6, quad meshes mostly 4; outliers are poles. See the Valence Heatmap render mode.")
        }
    }

    private func describe(_ component: SurfaceComponent) -> String {
        let genus = component.genus.map { "genus \($0)" } ?? "invalid genus"
        let orientation = component.isOrientable ? "" : ", non-orientable"
        return "\(component.faces.count) faces, \(genus)\(orientation)"
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
    @State private var exportFormat: PLY.Format = .ascii
    @State private var chamferDistance: Float = 0.05
    @State private var extrudeDistance: Float = 0.2

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
                        .help("Unique positions. Vertices split at UV or normal seams count separately.")
                    LabeledContent("Faces", value: "\(currentMesh.faceCount)")
                        .help("Polygons of any size, possibly with holes. Not necessarily triangles.")
                    LabeledContent("Edges", value: "\(currentMesh.edgeCount)")
                        .help("Undirected edges between vertices.")
                    LabeledContent("Half-Edges", value: "\(currentMesh.topology.halfEdges.count)")
                        .help("Directed edges, one per face corner. Interior edges have two (one per side), boundary edges one.")
                    LabeledContent("Submeshes", value: "\(currentMesh.submeshes.count)")
                        .help("Face groups, usually one per material. Each becomes a separate draw on export.")
                    LabeledContent("Manifold") {
                        Text(currentMesh.isManifold ? "Yes" : "No")
                            .foregroundStyle(currentMesh.isManifold ? .green : .red)
                    }
                    .help("Closed 2-manifold: no holes, every edge shared by exactly two faces, and no pinched vertices. Required for chamfer.")
                    LabeledContent("Standalone Faces", value: "\(standaloneFaceIDs?.count ?? 0)")
                        .help("Faces that share no edge with any other face. Highlighted when Highlight Standalone is on.")
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
                            .help("Select every edge touching this vertex.")

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
                                .help("Select the boundary of a face using this edge. A full face boundary enables Extrude Face.")
                                if let halfEdge = halfEdge(for: edge) {
                                    Button("Select Loop") {
                                        selectLoop(from: halfEdge)
                                    }
                                    .help("Extend to the edge loop through this edge: straight across 4-edge vertices, stopping at poles and boundaries.")
                                }
                                if let halfEdge = halfEdge(for: edge) {
                                    Button("Split Edge") {
                                        editSelection { $0.splitEdge(halfEdge) }
                                    }
                                    .help("Insert a vertex at the edge's midpoint. Adjacent triangles split in two; other faces just gain the vertex.")
                                    Button("Flip Edge") {
                                        editSelection { $0.flipEdge(halfEdge) }
                                    }
                                    .disabled(!canFlip(halfEdge))
                                    .help("Swap the diagonal shared by two triangles. Disabled on boundary edges, non-triangle faces, or when the other diagonal already exists.")
                                }
                            }
                            Button("Chamfer Selected (\(edges.count))") {
                                let halfEdges = Set(edges.compactMap(halfEdge(for:)))
                                editSelection { mesh in
                                    if let chamfered = mesh.chamfered(distance: chamferDistance, edges: halfEdges, attributes: .default) {
                                        mesh = chamfered
                                    }
                                }
                            }
                            .disabled(!currentMesh.isManifold)
                            .help("Bevel the selected edges with a flat strip. Needs a closed manifold mesh. Attributes are regenerated.")
                            Slider(value: $chamferDistance, in: 0.01...0.2) { Text("Chamfer") }
                                .help("How far the chamfer cuts into the faces on each side of the edge.")
                            if let face = face(boundedBy: edges) {
                                Button("Extrude Face") {
                                    editSelection { $0 = $0.extrudingFace(face, distance: extrudeDistance) }
                                }
                                .help("Push the selected face along its normal and add side walls.")
                                Slider(value: $extrudeDistance, in: -0.3...0.5) { Text("Distance") }
                                    .help("Extrusion distance. Negative values push the face inward.")
                            }
                        }
                        Button("Clear Selection") {
                            self.selection = nil
                        }
                        .help("Deselect everything.")
                    }
                }
                MeshDiagnosticsSection(report: MeshDiagnosticsReport(mesh: currentMesh))
                Section("Attributes") {
                    LabeledContent("Normals", value: currentMesh.normals != nil ? "✓" : "—")
                        .help("Per-corner surface normals for lighting. Per-corner means a vertex can have different values in different faces (hard edges).")
                    LabeledContent("UVs", value: currentMesh.textureCoordinates != nil ? "✓" : "—")
                        .help("Per-corner texture coordinates. Seams are corners with different UVs at the same vertex.")
                    LabeledContent("Tangents", value: currentMesh.tangents != nil ? "✓" : "—")
                        .help("Per-corner tangents (MikkTSpace) for normal mapping. Need normals and UVs.")
                    LabeledContent("Bitangents", value: currentMesh.bitangents != nil ? "✓" : "—")
                        .help("Per-corner bitangents, completing the tangent frame for normal mapping.")
                    LabeledContent("Colors", value: currentMesh.colors != nil ? "✓" : "—")
                        .help("Per-corner RGBA vertex colors.")
                }
                Section("Display") {
                    Toggle("Highlight Standalone", isOn: $showStandalone)
                        .help("Highlight faces that share no edge with another face.")
                    Toggle("Vertex Dots", isOn: $showVertexDots)
                        .help("Draw a dot at every vertex.")
                }
            }
            .inspectorColumnWidth(min: 220, ideal: 260, max: 320)
        }
        .toolbar {
            operationsMenu
            Menu {
                Button("PLY (ASCII)") {
                    exportFormat = .ascii
                    isExporting = true
                }
                Button("PLY (Binary)") {
                    exportFormat = .binaryLittleEndian
                    isExporting = true
                }
            } label: {
                Label("Export PLY", systemImage: "square.and.arrow.up")
            }
            .help("Save the current mesh as PLY. ASCII is readable text; binary is several times smaller and faster to load.")
            Toggle(isOn: $showInspector) {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help("Show mesh info, diagnostics, selection edits, and operations.")
        }
        .fileExporter(
            isPresented: $isExporting,
            document: PLYDocument(mesh: currentMesh, format: exportFormat),
            contentType: .ply,
            defaultFilename: "\(item.name).ply"
        ) { _ in }
        .onAppear { recomputeStandalone() }
    }

    /// Whole-mesh operations, grouped by purpose. Menu items can't show tooltips on macOS,
    /// so labels carry the key detail and the menu itself has the help.
    private var operationsMenu: some View {
        Menu {
            Section("Topology") {
                Button("Weld Close Vertices") { applyOperation { $0.welded(tolerance: 1e-4) } }
                Button("Triangulate") { applyOperation { $0.triangulated() } }
                Button("Merge Coplanar Faces") { applyOperation { $0.mergingCoplanarFaces() } }
            }
            Section("Refine") {
                Button("Subdivide (Loop, triangles)") { applyOperation { $0.loopSubdivided(iterations: 1) } }
                Button("Subdivide (Catmull-Clark, any polygons)") { applyOperation { $0.catmullClarkSubdivided(iterations: 1) } }
                Button("Decimate to 50%") { applyOperation { $0.decimated(ratio: 0.5) } }
            }
            Section("Orientation") {
                // Non-orientable meshes can't be fixed; leave them unchanged.
                Button("Fix Winding") { applyOperation { $0.withConsistentWinding() ?? $0 } }
                Button("Reverse Winding (Inside Out)") { applyOperation { $0.reversingWinding() } }
            }
            Section("Generate") {
                Button("Wireframe Prisms") { applyOperation { $0.wireframe(radius: 0.015, sides: 8) } }
                Button("Face Borders (Inside)") { applyOperation { $0.border(thickness: 0.02, direction: .inside) } }
                Button("Face Borders (Outside)") { applyOperation { $0.border(thickness: 0.02, direction: .outside) } }
            }
            Divider()
            Button("Reset to Original") {
                currentMesh = item.mesh
                isModified = false
                recomputeStandalone()
            }
            .disabled(!isModified)
        } label: {
            Label("Operations", systemImage: "wand.and.stars")
        }
        .help("Whole-mesh operations: weld, triangulate, merge coplanar faces, subdivide, decimate, fix or reverse winding, and generate wireframes or face borders. Reset returns to the gallery mesh.")
    }

    private func applyOperation(_ operation: (Mesh) -> Mesh) {
        currentMesh = operation(currentMesh)
        isModified = true
        recomputeStandalone()
    }

    private func recomputeStandalone() {
        standaloneFaceIDs = currentMesh.standaloneFaces()
    }

    // MARK: Selection edits

    /// Apply an in-place edit and clear the selection (indices may have changed).
    private func editSelection(_ edit: (inout Mesh) -> Void) {
        var mesh = currentMesh
        edit(&mesh)
        currentMesh = mesh
        isModified = true
        selection = nil
        recomputeStandalone()
    }

    private func halfEdge(for edge: MeshEdge) -> HalfEdgeTopology.HalfEdgeID? {
        currentMesh.topology.halfEdges.first { halfEdge in
            guard halfEdge.next != nil, let destination = currentMesh.topology.destViaNext(of: halfEdge.id) else {
                return false
            }
            return MeshEdge(halfEdge.origin.raw, destination.raw) == edge
        }?.id
    }

    private func selectLoop(from halfEdge: HalfEdgeTopology.HalfEdgeID) {
        let topology = currentMesh.topology
        let edges = topology.edgeLoop(from: halfEdge).compactMap { id -> MeshEdge? in
            topology.destViaNext(of: id).map { MeshEdge(topology.halfEdges[id.raw].origin.raw, $0.raw) }
        }
        selection = .edges(Set(edges))
    }

    private func canFlip(_ halfEdge: HalfEdgeTopology.HalfEdgeID) -> Bool {
        var trial = currentMesh.topology
        return trial.flipEdge(halfEdge)
    }

    /// The face whose outer boundary is exactly `edges`, if any.
    private func face(boundedBy edges: Set<MeshEdge>) -> HalfEdgeTopology.FaceID? {
        currentMesh.topology.faces.first { face in
            guard face.edge != nil else {
                return false
            }
            let loop = currentMesh.topology.vertexLoop(for: face.id)
            let boundary = Set(loop.indices.map { MeshEdge(loop[$0].raw, loop[($0 + 1) % loop.count].raw) })
            return boundary == edges
        }?.id
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
    /// What the section demonstrates and which API it uses; shown as hover help.
    let help: String
    let items: [MeshGalleryItem]

    init(_ name: String, help: String = "", items: [MeshGalleryItem]) {
        self.id = name
        self.name = name
        self.help = help
        self.items = items
    }

    /// Hover help for an item: its subtitle, then the section's API note.
    func help(for item: MeshGalleryItem) -> String {
        [item.subtitle, help.isEmpty ? nil : help].compactMap { $0 }.joined(separator: "\n\n")
    }

    static let all: [Self] = [
        Self("Platonic Solids", help: "The five regular polyhedra: Mesh.tetrahedron(), .cube(), .octahedron(), .icosahedron(), .dodecahedron(). Good small test inputs.", items: [
            MeshGalleryItem("Tetrahedron", mesh: .tetrahedron()),
            MeshGalleryItem("Cube", mesh: .cube()),
            MeshGalleryItem("Octahedron", mesh: .octahedron()),
            MeshGalleryItem("Icosahedron", mesh: .icosahedron()),
            MeshGalleryItem("Dodecahedron", mesh: .dodecahedron())
        ]),
        Self("Surfaces", help: "Parametric primitives such as Mesh.sphere(), .torus(), .cylinder(), .capsule(), .icoSphere(), and the Utah teapot. Most take extents, segment counts, and attributes.", items: [
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
        Self("CSG", help: "Boolean solids: mesh.union(_:), .intersection(_:), .difference(_:) (or csg(_:_:options:)). Robust Boolean ported from Manifold: closed manifold inputs always give a closed manifold result, with attributes interpolated.", items: {
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
        Self("2D CSG", help: "Planar booleans on Mesh2D: walls with door and window openings and a floor plan, built from line segments with face classification and holes.", items: {
            let t: Float = 0.02 // wall thickness

            // Wall with door
            let wall = Mesh.box(extents: [0.8, 0.5, t], attributes: [])
            let door = Mesh.box(extents: [0.18, 0.3, t * 2], attributes: []).translated(by: [0.1, -0.1, 0])
            let wallWithDoor = wall.difference(door)

            // Wall with window
            let window = Mesh.box(extents: [0.2, 0.15, t * 2], attributes: []).translated(by: [0, 0.05, 0])
            let wallWithWindow = wall.difference(window)

            // Wall with door + two windows
            let wallFull = wall
                .difference(door)
                .difference(Mesh.box(extents: [0.12, 0.12, t * 2], attributes: []).translated(by: [-0.25, 0.06, 0]))
                .difference(Mesh.box(extents: [0.12, 0.12, t * 2], attributes: []).translated(by: [0.3, 0.06, 0]))

            // Arch window (cylinder subtracted from wall)
            let archCutter = Mesh.cylinder(segments: 24, height: t * 2, radius: 0.1, attributes: [])
                .rotated(by: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
                .translated(by: [0, 0.08, 0])
            let rectCutter = Mesh.box(extents: [0.2, 0.18, t * 2], attributes: []).translated(by: [0, -0.04, 0])
            let archWindow = wall.difference(archCutter).difference(rectCutter)

            // Floor plan: four walls forming a room with a doorway
            let wallN = Mesh.box(extents: [0.6, t, 0.6], attributes: []).translated(by: [0, 0, -0.3])
            let wallS = Mesh.box(extents: [0.6, t, 0.6], attributes: []).translated(by: [0, 0, 0.3])
            let wallE = Mesh.box(extents: [t, t, 0.6], attributes: []).translated(by: [0.3, 0, 0])
            let wallW = Mesh.box(extents: [t, t, 0.6], attributes: []).translated(by: [-0.3, 0, 0])
            let doorCut = Mesh.box(extents: [0.15, t * 2, t * 2], attributes: []).translated(by: [0.05, 0, 0.3])
            let room = wallN.union(wallS).union(wallE).union(wallW).difference(doorCut)

            return [
                MeshGalleryItem("Wall + Door", subtitle: "Door cut from wall", mesh: wallWithDoor),
                MeshGalleryItem("Wall + Window", subtitle: "Window cut from wall", mesh: wallWithWindow),
                MeshGalleryItem("Wall + Door + Windows", subtitle: "Multiple cutouts", mesh: wallFull),
                MeshGalleryItem("Arch Window", subtitle: "Cylinder + rect cutout", mesh: archWindow),
                MeshGalleryItem("Floor Plan", subtitle: "Room with doorway", mesh: room)
            ]
        }()),
        Self("Subdivision", help: "Smoothing by refinement: mesh.loopSubdivided(iterations:) for triangles, .catmullClarkSubdivided(iterations:) for any polygons (produces quads).", items: [
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
        Self("Marching Cubes", help: "Isosurfaces of a scalar field: Mesh.marchingCubes(resolution:bounds:isoValue:field:). The surface is where the field equals isoValue.", items: {
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
        Self("Extrusion", help: "Solids from 2D outlines and spheres: Mesh.extruded(Path, depth:), Mesh.extrudedText(_:depth:), and Mesh.convexHull(ofSpheres:). Nested outlines become holes.", items: {
            func fitted(_ mesh: Mesh) -> Mesh {
                var mesh = mesh
                mesh.fitToExtents([0.8, 0.8, 0.8])
                return mesh
            }
            let star = Path { path in
                for index in 0..<10 {
                    let angle = Double(index) * .pi / 5 - .pi / 2
                    let radius: Double = index.isMultiple(of: 2) ? 1 : 0.45
                    let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
            }
            var frame = Path(roundedRect: CGRect(x: 0, y: 0, width: 2, height: 2), cornerRadius: 0.3)
            frame.addPath(Path(ellipseIn: CGRect(x: 0.5, y: 0.5, width: 1, height: 1)))
            let capsuleSpheres: [(center: SIMD3<Float>, radius: Float)] = [([-0.25, 0, 0], 0.15), ([0.25, 0, 0], 0.15)]
            let mixedSpheres: [(center: SIMD3<Float>, radius: Float)] = [([0, 0, 0], 0.25), ([0.35, 0.1, 0], 0.08), ([-0.1, 0.35, 0.1], 0.12), ([0, -0.1, 0.35], 0.05)]
            return [
                MeshGalleryItem("Star", subtitle: "Path extrusion", mesh: fitted(.extruded(star, depth: 0.3))),
                MeshGalleryItem("Rounded Rect", subtitle: "Curved path", mesh: fitted(.extruded(Path(roundedRect: CGRect(x: 0, y: 0, width: 2, height: 1), cornerRadius: 0.3), depth: 0.4))),
                MeshGalleryItem("Frame", subtitle: "Path with a hole", mesh: fitted(.extruded(frame, depth: 0.4))),
                MeshGalleryItem("Text", subtitle: "\"SwiftMesh\" in Helvetica", mesh: fitted(.extrudedText("SwiftMesh", depth: 0.2))),
                MeshGalleryItem("Text with Holes", subtitle: "\"BOQ\" in Helvetica Bold", mesh: fitted(.extrudedText("BOQ", fontName: "Helvetica-Bold", depth: 0.25))),
                MeshGalleryItem("Sphere Hull: Capsule", subtitle: "Two equal spheres", mesh: Mesh.convexHull(ofSpheres: capsuleSpheres, subdivisions: 3) ?? .tetrahedron()),
                MeshGalleryItem("Sphere Hull: Mixed", subtitle: "Four spheres, mixed radii", mesh: Mesh.convexHull(ofSpheres: mixedSpheres, subdivisions: 3) ?? .tetrahedron())
            ]
        }()),
        Self("Editing", help: "Local edits: splitEdge(_:at:), flipEdge(_:), extrudingFace(_:distance:), chamfered(distance:segments:edges:) (segments > 1 rounds it into a fillet), and split(planeNormal:point:capped:). Try the same edits interactively from the inspector's Selection section.", items: {
            // Split every 7th edge of an icosphere once.
            var split = Mesh.icoSphere(extents: [0.8, 0.8, 0.8], subdivisions: 1, attributes: [])
            for halfEdge in split.topology.halfEdges.indices where halfEdge.isMultiple(of: 7) {
                split.splitEdge(.init(raw: halfEdge))
            }
            // A strip of triangles with every other diagonal flipped.
            var stripPositions: [SIMD3<Float>] = []
            for column in 0...6 {
                let x = Float(column) * 0.13 - 0.4
                stripPositions.append([x, -0.15, 0])
                stripPositions.append([x, 0.15, 0])
            }
            var stripFaces: [[Int]] = []
            for column in 0..<6 {
                let base = 2 * column
                stripFaces.append([base, base + 2, base + 3])
                stripFaces.append([base, base + 3, base + 1])
            }
            var strip = Mesh(positions: stripPositions, faces: stripFaces)
            let unflipped = strip
            for halfEdge in strip.topology.halfEdges where halfEdge.twin != nil && halfEdge.id.raw < halfEdge.twin!.raw {
                // Diagonals join vertex 2c to 2c + 3; flip those in even columns.
                let ends = [halfEdge.origin.raw, strip.topology.destViaNext(of: halfEdge.id)!.raw].sorted()
                if ends[1] - ends[0] == 3, (ends[0] / 2).isMultiple(of: 2) {
                    strip.flipEdge(halfEdge.id)
                }
            }
            let box = Mesh.box(extents: [0.5, 0.5, 0.5], attributes: [])
            let topFace = box.topology.faces.first { box.faceNormal($0.id).y > 0.99 }!.id
            let sphere = Mesh.icoSphere(extents: [0.8, 0.8, 0.8], subdivisions: 3, attributes: [])
            let cutNormal = simd_normalize(SIMD3<Float>(1, 1, 0.3))
            return [
                MeshGalleryItem("Split Edges", subtitle: "Every 7th edge of an icosphere", mesh: split),
                MeshGalleryItem("Strip", subtitle: "Before flipping", mesh: unflipped),
                MeshGalleryItem("Flipped Strip", subtitle: "Alternate diagonals flipped", mesh: strip),
                MeshGalleryItem("Extrude Face", subtitle: "Box top pushed out", mesh: box.extrudingFace(topFace, distance: 0.3)),
                MeshGalleryItem("Inset Face", subtitle: "Box top pushed in", mesh: box.extrudingFace(topFace, distance: -0.2)),
                MeshGalleryItem("Chamfer All", subtitle: "Every box edge", mesh: box.chamfered(distance: 0.06, attributes: .default) ?? box),
                MeshGalleryItem("Chamfer One", subtitle: "A single box edge", mesh: box.chamfered(distance: 0.1, edges: [box.topology.halfEdges.first { $0.twin != nil }!.id], attributes: .default) ?? box),
                MeshGalleryItem("Chamfer Icosahedron", subtitle: "Every edge", mesh: Mesh.icosahedron(extents: [0.8, 0.8, 0.8], attributes: []).chamfered(distance: 0.05, attributes: .default) ?? box),
                MeshGalleryItem("Fillet All", subtitle: "Every box edge, 6 segments", mesh: box.chamfered(distance: 0.08, segments: 6, attributes: [.smoothNormals]) ?? box),
                MeshGalleryItem("Fillet One", subtitle: "A single box edge, 6 segments", mesh: box.chamfered(distance: 0.12, segments: 6, edges: [box.topology.halfEdges.first { $0.twin != nil }!.id], attributes: [.smoothNormals]) ?? box),
                MeshGalleryItem("Plane Split (Capped)", subtitle: "Sphere, front half", mesh: sphere.split(planeNormal: cutNormal, point: .zero).front),
                MeshGalleryItem("Plane Split (Open)", subtitle: "Sphere, front half, uncapped", mesh: sphere.split(planeNormal: cutNormal, point: .zero, capped: false).front),
                MeshGalleryItem("Torus Cut", subtitle: "Annulus cap with a hole", mesh: Mesh.torus(attributes: []).split(planeNormal: [0, 1, 0], point: .zero).front)
            ]
        }()),
        Self("Convex Hull", help: "Mesh.convexHull(of:): the smallest convex solid containing the points. Interior points are ignored.", items: {
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
        Self("Wireframe", help: "mesh.wireframe(radius:sides:): replaces every edge with a solid prism, for printable or renderable wireframes.", items: {
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
        Self("Border", help: "mesh.border(thickness:direction:): replaces each face with a frame along its edges, inset (inside) or grown (outside).", items: {
            let cube = Mesh.cube(attributes: [])
            let dodecahedron = Mesh.dodecahedron(attributes: [])
            let icosahedron = Mesh.icosahedron(attributes: [])
            let torus = Mesh.torus(majorSegments: 16, minorSegments: 8, attributes: [])
            return [
                MeshGalleryItem("Cube Border (Inside)", subtitle: "Inset quad strips",
                    mesh: cube.border(thickness: 0.05, direction: .inside)),
                MeshGalleryItem("Cube Border (Outside)", subtitle: "Outset quad strips",
                    mesh: cube.border(thickness: 0.05, direction: .outside)),
                MeshGalleryItem("Dodecahedron Border", subtitle: "Pentagon frames",
                    mesh: dodecahedron.border(thickness: 0.04, direction: .inside)),
                MeshGalleryItem("Icosahedron Border", subtitle: "Triangle frames",
                    mesh: icosahedron.border(thickness: 0.04, direction: .inside)),
                MeshGalleryItem("Torus Border", subtitle: "16×8 quad frames",
                    mesh: torus.border(thickness: 0.008, direction: .inside)),
                MeshGalleryItem("Cube Border (Tri)", subtitle: "Triangulated",
                    mesh: cube.border(thickness: 0.05, direction: .inside, triangulate: true))
            ]
        }()),
        Self("Decimation", help: "mesh.decimated(ratio:): quadric edge collapse that removes triangles while keeping the shape. Compare face counts in the subtitles.", items: {
            let sphere = Mesh.icoSphere(extents: [1, 1, 1], subdivisions: 3, attributes: [])
            let sphereFaces = sphere.topology.faces.filter { $0.edge != nil }.count
            return [
                MeshGalleryItem("IcoSphere", subtitle: "Original (\(sphereFaces) faces)", mesh: sphere),
                MeshGalleryItem("50%", subtitle: "\(sphereFaces / 2) faces", mesh: sphere.decimated(ratio: 0.5)),
                MeshGalleryItem("25%", subtitle: "\(sphereFaces / 4) faces", mesh: sphere.decimated(ratio: 0.25)),
                MeshGalleryItem("10%", subtitle: "\(sphereFaces / 10) faces", mesh: sphere.decimated(ratio: 0.1))
            ]
        }()),
        Self("Atlas Baking", help: "mesh.bakingPlanarAtlas(texelsPerMeter:atlasSize:padding:): groups coplanar faces into charts and packs them into one texture. View with UV Grid or Checkerboard; even squares mean uniform texel density.", items: {
            // Baked UVs are kept by the renderer; view with the UV Grid or Checkerboard debug mode.
            func baked(_ mesh: Mesh) -> Mesh {
                (try? mesh.bakingPlanarAtlas(texelsPerMeter: 256, atlasSize: [1_024, 1_024]).mesh) ?? mesh
            }
            let room = Mesh.box(extents: [0.8, 0.5, 0.6], attributes: [])
                .difference(Mesh.box(extents: [0.3, 0.3, 0.8], attributes: []).translated(by: [0.1, 0, 0]))
            return [
                MeshGalleryItem("Box Atlas", subtitle: "6 charts \u{2014} use UV Grid mode", mesh: baked(.box(extents: [0.6, 0.4, 0.5], attributes: []))),
                MeshGalleryItem("Frustum Atlas", subtitle: "Slanted charts \u{2014} use UV Grid mode", mesh: baked(.rectangularFrustum(attributes: []))),
                MeshGalleryItem("CSG Atlas", subtitle: "Box with a hole \u{2014} use Checkerboard mode", mesh: baked(room))
            ]
        }())
    ]
}

// MARK: - PLY Export

struct PLYDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.ply] }

    let data: Data

    init(mesh: Mesh, format: PLY.Format = .ascii) {
        self.data = PLY.write(mesh, format: format)
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
