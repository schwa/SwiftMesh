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
                backfaceCull: false
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

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MeshInteractiveView(mesh: mesh)
            VStack(alignment: .trailing) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding()
                Spacer()
                Text(name)
                    .font(.title2.bold())
                    .padding()
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 10)
    }
}

/// A gallery view showing all Platonic solids.
struct PlatonicSolidsGallery: View {
    @State private var selectedMesh: (String, Mesh)?

    var body: some View {
        let solids: [(String, Mesh)] = [
            ("Tetrahedron", .tetrahedron()),
            ("Cube", .cube()),
            ("Octahedron", .octahedron()),
            ("Icosahedron", .icosahedron()),
            ("Dodecahedron", .dodecahedron())
        ]

        ZStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250))], spacing: 20) {
                    ForEach(solids, id: \.0) { name, mesh in
                        MeshGridCell(name: name, mesh: mesh) {
                            withAnimation { selectedMesh = (name, mesh) }
                        }
                    }
                }
                .padding()
            }

            if let (name, mesh) = selectedMesh {
                MeshDetailView(name: name, mesh: mesh) {
                    withAnimation { selectedMesh = nil }
                }
                .padding()
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

/// A gallery view showing parametric surfaces.
struct ParametricSurfacesGallery: View {
    @State private var selectedMesh: (String, Mesh)?

    var body: some View {
        let surfaces: [(String, Mesh)] = [
            ("Sphere", .sphere()),
            ("Torus", .torus()),
            ("Cylinder", .cylinder()),
            ("Cone", .cone()),
            ("Box", .box()),
            ("Hemisphere", .hemisphere()),
            ("Capsule", .capsule()),
            ("Conical Frustum", .conicalFrustum()),
            ("Rect Frustum", .rectangularFrustum()),
            ("Circle", .circle()),
            ("Teapot", .teapot()),
            ("IcoSphere", .icoSphere()),
            ("CubeSphere", .cubeSphere())
        ]

        ZStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250))], spacing: 20) {
                    ForEach(surfaces, id: \.0) { name, mesh in
                        MeshGridCell(name: name, mesh: mesh) {
                            withAnimation { selectedMesh = (name, mesh) }
                        }
                    }
                }
                .padding()
            }

            if let (name, mesh) = selectedMesh {
                MeshDetailView(name: name, mesh: mesh) {
                    withAnimation { selectedMesh = nil }
                }
                .padding()
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
}
