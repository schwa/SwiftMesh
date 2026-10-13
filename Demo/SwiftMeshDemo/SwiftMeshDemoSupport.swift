import GeometryLite3D
import Interaction3D
import Metal
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsUI
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

// MARK: - Standalone face detection

extension Mesh {
    /// Returns face IDs where no edge of the face has a twin (completely isolated).
    func standaloneFaces() -> Set<HalfEdgeTopology.FaceID> {
        var result = Set<HalfEdgeTopology.FaceID>()
        for face in topology.faces {
            let edges = topology.halfEdgeLoop(for: face.id)
            let allBoundary = edges.allSatisfy { topology.halfEdges[$0.raw].twin == nil }
            if allBoundary {
                result.insert(face.id)
            }
        }
        return result
    }
}

// MARK: - Wireframe drawing

struct WireframeCamera {
    var viewMatrix: float4x4

    func projectionMatrix(aspectRatio: Float) -> float4x4 {
        PerspectiveProjection(verticalAngleOfView: .degrees(45)).projectionMatrix(aspectRatio: aspectRatio)
    }

    /// Projects a world-space point to view coordinates (origin top-left), or nil if behind the camera.
    func project(_ position: SIMD3<Float>, viewSize: CGSize) -> CGPoint? {
        guard viewSize.width > 0, viewSize.height > 0 else {
            return nil
        }
        let projection = projectionMatrix(aspectRatio: Float(viewSize.width / viewSize.height))
        let clip = projection * viewMatrix * SIMD4(position, 1)
        guard clip.w > Float.leastNormalMagnitude else {
            return nil
        }
        let ndc = clip / clip.w
        return CGPoint(x: CGFloat((ndc.x + 1) * 0.5) * viewSize.width, y: CGFloat((1 - ndc.y) * 0.5) * viewSize.height)
    }
}

extension Mesh {
    /// Every undirected edge as one stroke, plus optional face highlights.
    func wireframeContext(
        color: Color,
        lineWidth: Float,
        highlightedFaces: Set<HalfEdgeTopology.FaceID>? = nil,
        highlightColor: Color = Color(red: 1, green: 0, blue: 1)
    ) -> GraphicsContext3D {
        GraphicsContext3D { context in
            let edges = Path3D { path in
                for (a, b) in topology.undirectedEdges() {
                    path.move(to: positions[a.raw])
                    path.addLine(to: positions[b.raw])
                }
            }
            context.stroke(edges, with: color, lineWidth: lineWidth)

            if let highlightedFaces, !highlightedFaces.isEmpty {
                let outlines = Path3D { path in
                    for face in highlightedFaces {
                        let loop = topology.vertexLoop(for: face)
                        guard let first = loop.first else {
                            continue
                        }
                        path.move(to: positions[first.raw])
                        for vertex in loop.dropFirst() {
                            path.addLine(to: positions[vertex.raw])
                        }
                        path.closeSubpath()
                    }
                }
                context.stroke(outlines, with: highlightColor, lineWidth: lineWidth * 3)
            }
        }
    }
}

extension GraphicsContext3D {
    /// A screen-space dot: a tiny segment drawn with round caps.
    mutating func dot(at position: SIMD3<Float>, color: Color, diameter: Float) {
        let path = Path3D { path in
            path.move(to: position)
            path.addLine(to: position + SIMD3<Float>(repeating: 1e-5))
        }
        stroke(path, with: color, style: StrokeStyle(lineWidth: CGFloat(diameter), lineCap: .round))
    }
}

/// Renders a `GraphicsContext3D` over a transparent background.
struct WireframeRenderView: View {
    let context: GraphicsContext3D
    let camera: WireframeCamera

    var body: some View {
        RenderView { _, drawableSize in
            let aspect = drawableSize.height > 0 ? Float(drawableSize.width / drawableSize.height) : 1
            try RenderPass(label: "Wireframe") {
                GraphicsContext3DRenderPipeline(
                    context: context,
                    viewProjection: camera.projectionMatrix(aspectRatio: aspect) * camera.viewMatrix,
                    viewport: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
                )
            }
        }
        .metalClearColor(MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0))
        .metalDepthStencilPixelFormat(.depth32Float)
    }
}

// MARK: - Static Preview

/// A static wireframe preview of a mesh (no interaction).
struct MeshPreviewView: View {
    let mesh: Mesh

    var body: some View {
        WireframeRenderView(
            context: mesh.wireframeContext(color: .black, lineWidth: 1),
            camera: WireframeCamera(viewMatrix: float4x4(translation: [0, 0, 4]).inverse)
        )
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

    private var camera: WireframeCamera {
        let viewMatrix = (float4x4(translation: cameraTarget) * float4x4(cameraRotation) * float4x4(translation: [0, 0, cameraDistance])).inverse
        return WireframeCamera(viewMatrix: viewMatrix)
    }

    private var context: GraphicsContext3D {
        var context = mesh.wireframeContext(color: .black.opacity(0.3), lineWidth: 1, highlightedFaces: highlightedFaces)
        if showVertexDots {
            for position in mesh.positions {
                context.dot(at: position, color: .black.opacity(0.4), diameter: 8)
            }
        }
        switch selection {
        case .vertex(let index):
            context.dot(at: mesh.positions[index], color: .red, diameter: 16)

        case .edges(let edges):
            let path = Path3D { path in
                for edge in edges {
                    path.move(to: mesh.positions[edge.a])
                    path.addLine(to: mesh.positions[edge.b])
                }
            }
            context.stroke(path, with: .red, lineWidth: 4)

        case nil:
            break
        }
        return context
    }

    var body: some View {
        WireframeRenderView(context: context, camera: camera)
            .contentShape(Rectangle())
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

    private func hitTest(at location: CGPoint) {
        let camera = camera

        var bestVertexDistance: CGFloat = .infinity
        var bestVertexIndex: Int?
        for (index, position) in mesh.positions.enumerated() {
            guard let point = camera.project(position, viewSize: viewSize) else { continue }
            let distance = hypot(point.x - location.x, point.y - location.y)
            if distance < hitThreshold, distance < bestVertexDistance {
                bestVertexDistance = distance
                bestVertexIndex = index
            }
        }
        if let index = bestVertexIndex {
            selection = .vertex(index)
            return
        }

        var bestEdgeDistance: CGFloat = .infinity
        var bestEdge: MeshEdge?
        for (vertexA, vertexB) in mesh.topology.undirectedEdges() {
            guard let pointA = camera.project(mesh.positions[vertexA.raw], viewSize: viewSize),
                  let pointB = camera.project(mesh.positions[vertexB.raw], viewSize: viewSize) else { continue }
            let distance = pointToSegmentDistance(point: location, segmentA: pointA, segmentB: pointB)
            if distance < hitThreshold, distance < bestEdgeDistance {
                bestEdgeDistance = distance
                bestEdge = MeshEdge(vertexA.raw, vertexB.raw)
            }
        }
        if let edge = bestEdge {
            selection = .edges([edge])
            return
        }

        selection = nil
    }

    private func pointToSegmentDistance(point: CGPoint, segmentA: CGPoint, segmentB: CGPoint) -> CGFloat {
        let dx = segmentB.x - segmentA.x
        let dy = segmentB.y - segmentA.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - segmentA.x, point.y - segmentA.y)
        }
        let t = max(0, min(1, ((point.x - segmentA.x) * dx + (point.y - segmentA.y) * dy) / lengthSquared))
        return hypot(point.x - (segmentA.x + t * dx), point.y - (segmentA.y + t * dy))
    }
}
