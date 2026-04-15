import GeometryLite3D
import Interaction3D
import simd
import SwiftMesh
import SwiftUI

// MARK: - Selection

enum MeshSelection: Equatable {
    case vertex(Int)
    case edge(Int, Int) // vertex indices (sorted)
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
                            case .edge(let a, let b):
                                LabeledContent("Type", value: "Edge")
                                LabeledContent("Vertices", value: "\(a) — \(b)")
                                let posA = mesh.positions[a]
                                let posB = mesh.positions[b]
                                let length = simd_length(posB - posA)
                                LabeledContent("Length", value: String(format: "%.4f", length))
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

    private let hitThreshold: CGFloat = 8

    var body: some View {
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
                case .edge(let a, let b):
                    if let ptA = renderer.project(mesh.positions[a]),
                       let ptB = renderer.project(mesh.positions[b]) {
                        var path = Path()
                        path.move(to: ptA)
                        path.addLine(to: ptB)
                        context.stroke(path, with: .color(.red), lineWidth: 2)
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
    }

    @State private var viewSize: CGSize = .zero

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

        // Check vertices first (higher priority)
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
        var bestEdge: (Int, Int)?
        for (vA, vB) in edges {
            guard let ptA = renderer.project(mesh.positions[vA.raw]),
                  let ptB = renderer.project(mesh.positions[vB.raw]) else { continue }
            let dist = pointToSegmentDistance(point: location, segA: ptA, segB: ptB)
            if dist < hitThreshold && dist < bestEdgeDist {
                bestEdgeDist = dist
                bestEdge = (min(vA.raw, vB.raw), max(vA.raw, vB.raw))
            }
        }
        if let (a, b) = bestEdge {
            selection = .edge(a, b)
            return
        }

        selection = nil
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
