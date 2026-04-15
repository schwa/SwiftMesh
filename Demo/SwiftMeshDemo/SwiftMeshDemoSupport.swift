import GeometryLite3D
import Interaction3D
import simd
import SwiftMesh
import SwiftUI

/// Display options for ``MeshCanvasView``.
struct MeshDisplayOptions {
    var showEdges: Bool = true
    var darkEdges: Bool = false
    var showFill: Bool = true
}

/// A view that renders a Mesh in 3D using SwiftUI Canvas with painter's algorithm.
struct MeshCanvasView: View {
    let mesh: Mesh
    let fillColor: Color
    @Binding var displayOptions: MeshDisplayOptions

    @State private var cameraRotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])
    @State private var cameraDistance: Float = 4
    @State private var cameraTarget: SIMD3<Float> = .zero

    init(mesh: Mesh, fillColor: Color = .blue, displayOptions: Binding<MeshDisplayOptions> = .constant(MeshDisplayOptions())) {
        self.mesh = mesh
        self.fillColor = fillColor
        self._displayOptions = displayOptions
    }

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

            let edgeColor: Color = displayOptions.showEdges ? (displayOptions.darkEdges ? .black : .white) : .clear

            mesh.draw(
                in: &context,
                renderer: renderer,
                fillColor: displayOptions.showFill ? fillColor : .clear,
                strokeColor: edgeColor,
                lineWidth: displayOptions.showEdges ? 0.5 : 0,
                backfaceCull: displayOptions.showFill
            )
        }
        .interactiveCamera(
            rotation: $cameraRotation,
            distance: $cameraDistance,
            target: $cameraTarget
        )
    }
}

/// Toolbar toggles for mesh display options.
struct MeshDisplayToolbar: ToolbarContent {
    @Binding var options: MeshDisplayOptions

    var body: some ToolbarContent {
        ToolbarItemGroup {
            Toggle(isOn: $options.showFill) {
                Label("Fill", systemImage: "square.fill")
            }
            Toggle(isOn: $options.showEdges) {
                Label("Edges", systemImage: "square.on.square")
            }
            if options.showEdges {
                Toggle(isOn: $options.darkEdges) {
                    Label("Dark Edges", systemImage: "circle.lefthalf.filled")
                }
            }
        }
    }
}

/// A gallery view showing all Platonic solids.
struct PlatonicSolidsGallery: View {
    @State private var displayOptions = MeshDisplayOptions()

    var body: some View {
        let solids: [(String, Mesh, Color)] = [
            ("Tetrahedron", .tetrahedron(), .red),
            ("Cube", .cube(), .blue),
            ("Octahedron", .octahedron(), .green),
            ("Icosahedron", .icosahedron(), .orange),
            ("Dodecahedron", .dodecahedron(), .purple)
        ]

        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250))], spacing: 20) {
                ForEach(solids, id: \.0) { name, mesh, color in
                    VStack {
                        MeshCanvasView(mesh: mesh, fillColor: color, displayOptions: $displayOptions)
                            .frame(height: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Text(name)
                            .font(.headline)
                    }
                }
            }
            .padding()
        }
        .toolbar {
            MeshDisplayToolbar(options: $displayOptions)
        }
    }
}

/// A gallery view showing parametric surfaces.
struct ParametricSurfacesGallery: View {
    @State private var displayOptions = MeshDisplayOptions()

    var body: some View {
        let surfaces: [(String, Mesh, Color)] = [
            ("Sphere", .sphere(), .cyan),
            ("Torus", .torus(), .pink),
            ("Cylinder", .cylinder(), .mint),
            ("Cone", .cone(), .indigo),
            ("Box", .box(), .teal),
            ("Hemisphere", .hemisphere(), .orange),
            ("Capsule", .capsule(), .purple),
            ("Conical Frustum", .conicalFrustum(), .brown),
            ("Rect Frustum", .rectangularFrustum(), .gray),
            ("Circle", .circle(), .yellow),
            ("Teapot", .teapot(), .red),
            ("IcoSphere", .icoSphere(), .red),
            ("CubeSphere", .cubeSphere(), .green)
        ]

        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250))], spacing: 20) {
                ForEach(surfaces, id: \.0) { name, mesh, color in
                    VStack {
                        MeshCanvasView(mesh: mesh, fillColor: color, displayOptions: $displayOptions)
                            .frame(height: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Text(name)
                            .font(.headline)
                    }
                }
            }
            .padding()
        }
        .toolbar {
            MeshDisplayToolbar(options: $displayOptions)
        }
    }
}
