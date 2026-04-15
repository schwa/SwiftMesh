import GeometryLite3D
import Interaction3D
import simd
import SwiftMesh
import SwiftUI

// MARK: - Selection

struct MeshEdge: Hashable {
    let a: Int
    let b: Int
    init(_ a: Int, _ b: Int) {
        self.a = min(a, b)
        self.b = max(a, b)
    }
}

enum MeshSelection: Equatable {
    case vertex(Int)
    case edges(Set<MeshEdge>)
}

// MARK: - Edge Loop

extension HalfEdgeTopology {
    /// Find the edge loop passing through the given edge.
    ///
    /// Walks in both directions from the edge, at each quad face crossing
    /// to the opposite edge. Stops at non-quad faces or boundaries.
    func edgeLoop(from vA: VertexID, to vB: VertexID) -> [(VertexID, VertexID)] {
        var loop: [(VertexID, VertexID)] = [(vA, vB)]
        var visited = Set<MeshEdge>()
        visited.insert(MeshEdge(vA.raw, vB.raw))

        // Walk in both directions
        for startDirection in [true, false] {
            var currentA = startDirection ? vA : vB
            var currentB = startDirection ? vB : vA

            while true {
                // Find the half-edge from currentA to currentB
                guard let heID = findHalfEdge(from: currentA, to: currentB) else { break }
                // Get the face on this side
                guard let faceID = halfEdges[heID.raw].face else { break }
                let faceVerts = vertexLoop(for: faceID)
                // Only continue through quad faces
                guard faceVerts.count == 4 else { break }
                // Find the opposite edge in the quad
                guard let idx = faceVerts.firstIndex(where: { $0 == currentA }) else { break }
                let oppositeA = faceVerts[(idx + 2) % 4]
                let oppositeB = faceVerts[(idx + 3) % 4]

                let edge = MeshEdge(oppositeA.raw, oppositeB.raw)
                guard !visited.contains(edge) else { break }
                visited.insert(edge)

                if startDirection {
                    loop.append((oppositeA, oppositeB))
                } else {
                    loop.insert((oppositeA, oppositeB), at: 0)
                }

                // Continue from the opposite edge, crossing through its twin
                guard let twinHE = findHalfEdge(from: oppositeB, to: oppositeA) else { break }
                guard halfEdges[twinHE.raw].twin != nil else { break }
                currentA = oppositeA
                currentB = oppositeB
            }
        }

        return loop
    }

    /// Find the half-edge going from `origin` to `dest`.
    private func findHalfEdge(from origin: VertexID, to dest: VertexID) -> HalfEdgeID? {
        // Check all half-edges originating from `origin`
        for he in halfEdges where he.origin == origin {
            if let next = he.next, halfEdges[next.raw].origin == dest {
                return he.id
            }
        }
        return nil
    }
}

// MARK: - Inspector View

struct InspectorView: View {
    @State private var mesh: Mesh = .cylinder()
    @State private var showInspector = true
    @State private var selection: MeshSelection?

    var body: some View {
        InspectorMeshView(mesh: mesh, selection: $selection)
            .inspector(isPresented: $showInspector) {
                Form {
                    Section("Topology") {
                        LabeledContent("Vertices", value: "\(mesh.vertexCount)")
                        LabeledContent("Faces", value: "\(mesh.faceCount)")
                        LabeledContent("Edges", value: "\(mesh.edgeCount)")
                        LabeledContent("Half-Edges", value: "\(mesh.topology.halfEdges.count)")
                        LabeledContent("Submeshes", value: "\(mesh.submeshes.count)")
                    }
                    Section("Attributes") {
                        LabeledContent("Normals", value: mesh.normals != nil ? "✓" : "—")
                        LabeledContent("UVs", value: mesh.textureCoordinates != nil ? "✓" : "—")
                        LabeledContent("Tangents", value: mesh.tangents != nil ? "✓" : "—")
                        LabeledContent("Bitangents", value: mesh.bitangents != nil ? "✓" : "—")
                        LabeledContent("Colors", value: mesh.colors != nil ? "✓" : "—")
                    }
                    if let selection {
                        Section("Selection") {
                            switch selection {
                            case .vertex(let idx):
                                LabeledContent("Type", value: "Vertex")
                                LabeledContent("Index", value: "\(idx)")
                                let pos = mesh.positions[idx]
                                LabeledContent("Position", value: String(format: "(%.3f, %.3f, %.3f)", pos.x, pos.y, pos.z))
                            case .edges(let edges):
                                LabeledContent("Type", value: "Edge\(edges.count == 1 ? "" : "s")")
                                LabeledContent("Count", value: "\(edges.count)")
                                if edges.count == 1, let edge = edges.first {
                                    LabeledContent("Vertices", value: "\(edge.a) — \(edge.b)")
                                    let length = simd_length(mesh.positions[edge.b] - mesh.positions[edge.a])
                                    LabeledContent("Length", value: String(format: "%.4f", length))
                                }
                            }
                        }
                    }
                }
                .inspectorColumnWidth(min: 200, ideal: 250, max: 300)
            }
            .toolbar {
                Toggle(isOn: $showInspector) {
                    Label("Inspector", systemImage: "sidebar.right")
                }
            }
    }
}

// MARK: - Interactive Mesh View with Hit Testing

struct InspectorMeshView: View {
    let mesh: Mesh
    @Binding var selection: MeshSelection?

    @State private var cameraRotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])
    @State private var cameraDistance: Float = 4
    @State private var cameraTarget: SIMD3<Float> = .zero
    @State private var viewSize: CGSize = .zero

    private let hitThreshold: CGFloat = 8

    var body: some View {
        ZStack(alignment: .bottom) {
            Canvas { context, size in
                let renderer = makeRenderer(size: size)

                // Draw wireframe
                mesh.draw(
                    in: &context,
                    renderer: renderer,
                    fillColor: .clear,
                    strokeColor: .black,
                    lineWidth: 0.5,
                    backfaceCull: false
                )

                // Draw highlighted selection
                if let selection {
                    switch selection {
                    case .vertex(let idx):
                        if let pt = renderer.project(mesh.positions[idx]) {
                            let rect = CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)
                            context.fill(Path(ellipseIn: rect), with: .color(.red))
                        }
                    case .edges(let edges):
                        for edge in edges {
                            if let ptA = renderer.project(mesh.positions[edge.a]),
                               let ptB = renderer.project(mesh.positions[edge.b]) {
                                var path = Path()
                                path.move(to: ptA)
                                path.addLine(to: ptB)
                                context.stroke(path, with: .color(.red), lineWidth: 2)
                            }
                        }
                    }
                }

                // Draw all vertices as small dots
                for pos in mesh.positions {
                    if let pt = renderer.project(pos) {
                        let rect = CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)
                        context.fill(Path(ellipseIn: rect), with: .color(.black.opacity(0.4)))
                    }
                }
            }
            .onTapGesture { location in
                hitTest(at: location)
            }
            .onGeometryChange(for: CGSize.self, of: \.size) { viewSize = $0 }
            .interactiveCamera(
                rotation: $cameraRotation,
                distance: $cameraDistance,
                target: $cameraTarget
            )

            // Bottom overlay toolbar
            if selection != nil {
                HStack(spacing: 12) {
                    if case .edges(let edges) = selection, edges.count == 1 {
                        Button("Select Loop") {
                            selectEdgeLoop()
                        }
                    }
                    Button("Clear") {
                        selection = nil
                    }
                }
                .buttonStyle(.bordered)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(.bottom, 12)
            }
        }
    }

    private func makeRenderer(size: CGSize) -> SoftwareRenderer {
        let s = size == .zero ? viewSize : size
        let fov = PerspectiveProjection(verticalAngleOfView: .degrees(45))
        let projectionMatrix = fov.projectionMatrix(width: Float(s.width), height: Float(s.height))
        let rotationMatrix = float4x4(cameraRotation)
        let viewMatrix = (float4x4(translation: cameraTarget) * rotationMatrix * float4x4(translation: [0, 0, cameraDistance])).inverse
        return SoftwareRenderer(viewMatrix: viewMatrix, projectionMatrix: projectionMatrix, viewportSize: s)
    }

    private func hitTest(at location: CGPoint) {
        let renderer = makeRenderer(size: viewSize)

        // Check vertices first
        var bestVertexDist: CGFloat = .infinity
        var bestVertexIdx: Int?
        for (idx, pos) in mesh.positions.enumerated() {
            guard let pt = renderer.project(pos) else { continue }
            let dist = hypot(pt.x - location.x, pt.y - location.y)
            if dist < hitThreshold && dist < bestVertexDist {
                bestVertexDist = dist
                bestVertexIdx = idx
            }
        }
        if let idx = bestVertexIdx {
            selection = .vertex(idx)
            return
        }

        // Check edges
        let edges = mesh.topology.undirectedEdges()
        var bestEdgeDist: CGFloat = .infinity
        var bestEdge: MeshEdge?
        for (vA, vB) in edges {
            guard let ptA = renderer.project(mesh.positions[vA.raw]),
                  let ptB = renderer.project(mesh.positions[vB.raw]) else { continue }
            let dist = pointToSegmentDistance(point: location, segA: ptA, segB: ptB)
            if dist < hitThreshold && dist < bestEdgeDist {
                bestEdgeDist = dist
                bestEdge = MeshEdge(vA.raw, vB.raw)
            }
        }
        if let edge = bestEdge {
            selection = .edges([edge])
            return
        }

        selection = nil
    }

    private func selectEdgeLoop() {
        guard case .edges(let edges) = selection, edges.count == 1, let edge = edges.first else { return }
        let loop = mesh.topology.edgeLoop(
            from: HalfEdgeTopology.VertexID(raw: edge.a),
            to: HalfEdgeTopology.VertexID(raw: edge.b)
        )
        let loopEdges = Set(loop.map { MeshEdge($0.0.raw, $0.1.raw) })
        selection = .edges(loopEdges)
    }

    private func pointToSegmentDistance(point: CGPoint, segA: CGPoint, segB: CGPoint) -> CGFloat {
        let dx = segB.x - segA.x
        let dy = segB.y - segA.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else {
            return hypot(point.x - segA.x, point.y - segA.y)
        }
        let t = max(0, min(1, ((point.x - segA.x) * dx + (point.y - segA.y) * dy) / lenSq))
        let projX = segA.x + t * dx
        let projY = segA.y + t * dy
        return hypot(point.x - projX, point.y - projY)
    }
}

#Preview {
    InspectorView()
}
