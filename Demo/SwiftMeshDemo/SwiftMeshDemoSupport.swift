import GeometryLite3D
import Interaction3D
import simd
import SwiftMesh
import SwiftUI

/// A view that renders a Mesh in 3D wireframe using SwiftUI Canvas.
struct MeshCanvasView: View {
    let mesh: Mesh
    let fillColor: Color

    @State private var cameraRotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])
    @State private var cameraDistance: Float = 4
    @State private var cameraTarget: SIMD3<Float> = .zero

    init(mesh: Mesh, fillColor: Color = .blue) {
        self.mesh = mesh
        self.fillColor = fillColor
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

/// A gallery view showing all Platonic solids.
struct PlatonicSolidsGallery: View {
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
                        MeshCanvasView(mesh: mesh, fillColor: color)
                            .frame(height: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Text(name)
                            .font(.headline)
                    }
                }
            }
            .padding()
        }
    }
}

/// A gallery view showing parametric surfaces.
struct ParametricSurfacesGallery: View {
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
                        MeshCanvasView(mesh: mesh, fillColor: color)
                            .frame(height: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Text(name)
                            .font(.headline)
                    }
                }
            }
            .padding()
        }
    }
}
