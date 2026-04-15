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
