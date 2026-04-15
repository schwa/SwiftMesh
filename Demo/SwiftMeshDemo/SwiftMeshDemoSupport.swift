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

// MARK: - Static Preview

/// A static wireframe preview of a mesh (no interaction).
struct MeshPreviewView: View {
    let mesh: Mesh

    var body: some View {
        Canvas { context, size in
            let fov = PerspectiveProjection(verticalAngleOfView: .degrees(45))
            let projectionMatrix = fov.projectionMatrix(width: Float(size.width), height: Float(size.height))
            let viewMatrix = float4x4(translation: [0, 0, 4]).inverse

            let renderer = SoftwareRenderer(
                viewMatrix: viewMatrix,
                projectionMatrix: projectionMatrix,
                viewportSize: size
            )

            mesh.draw(
                in: &context,
                renderer: renderer,
                fillColor: .clear,
                strokeColor: .black,
                lineWidth: 0.5,
                backfaceCull: false
            )
        }
    }
}

// MARK: - Interactive View

/// An interactive wireframe view of a mesh with camera controls and hit-testing.
struct MeshInteractiveView: View {
    let mesh: Mesh
    var highlightedFaces: Set<HalfEdgeTopology.FaceID>?
    var showVertexDots: Bool = false
    @Binding var selection: MeshSelection?

    @State private var cameraRotation = simd_quatf(angle: 0, axis: [0, 1, 0])
    @State private var cameraDistance: Float = 4
    @State private var cameraTarget: SIMD3<Float> = .zero
    @State private var viewSize: CGSize = .zero

    private let hitThreshold: CGFloat = 8

    init(mesh: Mesh, highlightedFaces: Set<HalfEdgeTopology.FaceID>? = nil, showVertexDots: Bool = false, selection: Binding<MeshSelection?> = .constant(nil)) {
        self.mesh = mesh
        self.highlightedFaces = highlightedFaces
        self.showVertexDots = showVertexDots
        self._selection = selection
    }

    var body: some View {
        Canvas { context, size in
            let renderer = makeRenderer(size: size)

            mesh.draw(
                in: &context,
                renderer: renderer,
                fillColor: .clear,
                strokeColor: .black,
                lineWidth: 0.5,
                backfaceCull: false,
                highlightedFaces: highlightedFaces,
                highlightStrokeColor: Color(red: 1, green: 0, blue: 1)
            )

            // Draw selection overlay
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

            // Draw vertex dots
            if showVertexDots {
                for pos in mesh.positions {
                    if let pt = renderer.project(pos) {
                        let rect = CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)
                        context.fill(Path(ellipseIn: rect), with: .color(.black.opacity(0.4)))
                    }
                }
            }
        }
        .onTapGesture { location in
            hitTest(at: location)
        }
        .accessibilityAddTraits(.isButton)
        .onGeometryChange(for: CGSize.self, of: \.size) { viewSize = $0 }
        .interactiveCamera(
            rotation: $cameraRotation,
            distance: $cameraDistance,
            target: $cameraTarget
        )
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

        // Vertices first
        var bestVertexDist: CGFloat = .infinity
        var bestVertexIdx: Int?
        for (idx, pos) in mesh.positions.enumerated() {
            guard let pt = renderer.project(pos) else { continue }
            let dist = hypot(pt.x - location.x, pt.y - location.y)
            if dist < hitThreshold, dist < bestVertexDist {
                bestVertexDist = dist
                bestVertexIdx = idx
            }
        }
        if let idx = bestVertexIdx {
            selection = .vertex(idx)
            return
        }

        // Edges
        let edges = mesh.topology.undirectedEdges()
        var bestEdgeDist: CGFloat = .infinity
        var bestEdge: MeshEdge?
        for (vA, vB) in edges {
            guard let ptA = renderer.project(mesh.positions[vA.raw]),
                  let ptB = renderer.project(mesh.positions[vB.raw]) else { continue }
            let dist = pointToSegmentDistance(point: location, segA: ptA, segB: ptB)
            if dist < hitThreshold, dist < bestEdgeDist {
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
