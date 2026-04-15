import GeometryLite3D
import Interaction3D
import simd
import SwiftMesh
import SwiftUI

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

/// An interactive wireframe view of a mesh with camera controls.
struct MeshInteractiveView: View {
    let mesh: Mesh
    var highlightedFaces: Set<HalfEdgeTopology.FaceID>?

    @State private var cameraRotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])
    @State private var cameraDistance: Float = 4
    @State private var cameraTarget: SIMD3<Float> = .zero

    var body: some View {
        Canvas { context, size in
            let fov = PerspectiveProjection(verticalAngleOfView: .degrees(45))
            let projectionMatrix = fov.projectionMatrix(width: Float(size.width), height: Float(size.height))

            let rotationMatrix = float4x4(cameraRotation)
            let viewMatrix = (float4x4(translation: cameraTarget) * rotationMatrix * float4x4(translation: [0, 0, cameraDistance])).inverse

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
                backfaceCull: false,
                highlightedFaces: highlightedFaces,
                highlightStrokeColor: Color(red: 1, green: 0, blue: 1)
            )
        }
        .interactiveCamera(
            rotation: $cameraRotation,
            distance: $cameraDistance,
            target: $cameraTarget
        )
    }
}

/// A mesh grid cell that can be tapped to expand.
struct MeshGridCell: View {
    let name: String
    let mesh: Mesh
    let subtitle: String?
    let action: () -> Void

    init(name: String, mesh: Mesh, subtitle: String? = nil, action: @escaping () -> Void) {
        self.name = name
        self.mesh = mesh
        self.subtitle = subtitle
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack {
                MeshPreviewView(mesh: mesh)
                    .frame(height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text(name)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Expanded detail view for an interactive mesh.
struct MeshDetailView: View {
    let name: String
    let mesh: Mesh
    let onDismiss: () -> Void

    @State private var displayMesh: Mesh?
    @State private var isTriangulated = false
    @State private var showStandalone = true
    @State private var standaloneFaceIDs: Set<HalfEdgeTopology.FaceID>?
    @State private var decimationRatio: Float = 1.0
    @State private var subdivisionLevel: Int = 0

    private var currentMesh: Mesh {
        displayMesh ?? mesh
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MeshInteractiveView(
                mesh: currentMesh,
                highlightedFaces: showStandalone ? standaloneFaceIDs : nil
            )
            VStack(alignment: .trailing) {
                HStack(spacing: 6) {
                    Toggle("Triangulate", isOn: $isTriangulated)
                        .onChange(of: isTriangulated) { rebuildDisplayMesh() }

                    Toggle("Standalone", isOn: $showStandalone)
                        .onChange(of: showStandalone) { if showStandalone { recomputeStandalone() } }
                        .tint(Color(red: 1, green: 0, blue: 1))

                    Button("Subdivide") {
                        subdivisionLevel += 1
                        rebuildDisplayMesh()
                    }
                    .disabled(subdivisionLevel >= 4)

                    Button("Decimate") {
                        decimationRatio = max(0.05, decimationRatio - 0.25)
                        rebuildDisplayMesh()
                    }
                    .disabled(decimationRatio <= 0.05)

                    if subdivisionLevel > 0 || decimationRatio < 1.0 {
                        Button("Reset") {
                            subdivisionLevel = 0
                            decimationRatio = 1.0
                            rebuildDisplayMesh()
                        }
                    }

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .padding()
                Spacer()
                HStack(spacing: 6) {
                    if isTriangulated {
                        Text("Triangulated")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if subdivisionLevel > 0 {
                        Text(isTriangulated ? "Loop ×\(subdivisionLevel)" : "CC ×\(subdivisionLevel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if decimationRatio < 1.0 {
                        Text("\(Int(decimationRatio * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if isTriangulated || subdivisionLevel > 0 || decimationRatio < 1.0 {
                        Text("\(currentMesh.faceCount) faces")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if showStandalone, let ids = standaloneFaceIDs {
                        Text("\(ids.count) standalone")
                            .font(.caption)
                            .foregroundStyle(Color(red: 1, green: 0, blue: 1))
                    }
                    Text(name)
                        .font(.title2.bold())
                }
                .padding()
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 10)
        .onAppear { recomputeStandalone() }
    }

    private var isModified: Bool {
        isTriangulated || subdivisionLevel > 0 || decimationRatio < 1.0
    }

    private func rebuildDisplayMesh() {
        var result = mesh
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
}
