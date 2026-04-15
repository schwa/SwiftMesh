import GeometryLite3D
import simd
import SwiftMesh
import SwiftUI

// MARK: - Projection

struct SoftwareRenderer {
    var viewMatrix: float4x4
    var projectionMatrix: float4x4
    var viewportSize: CGSize

    init(viewMatrix: float4x4, projectionMatrix: float4x4, viewportSize: CGSize) {
        self.viewMatrix = viewMatrix
        self.projectionMatrix = projectionMatrix
        self.viewportSize = viewportSize
    }

    /// Project a 3D point to 2D screen coordinates.
    func project(_ position: SIMD3<Float>, modelMatrix: float4x4 = .identity) -> CGPoint? {
        let clip = projectionMatrix * viewMatrix * modelMatrix * SIMD4(position, 1)
        guard abs(clip.w) > Float.leastNormalMagnitude else {
            return nil
        }
        let ndc = clip / clip.w
        // NDC to screen: x [-1,1] → [0, width], y [-1,1] → [height, 0]
        let x = CGFloat((ndc.x + 1) * 0.5) * viewportSize.width
        let y = CGFloat((1 - ndc.y) * 0.5) * viewportSize.height
        return CGPoint(x: x, y: y)
    }

    /// Create a SwiftUI Path from a polygon of 3D points.
    func path(for points: [SIMD3<Float>], modelMatrix: float4x4 = .identity) -> Path {
        let projected = points.compactMap { project($0, modelMatrix: modelMatrix) }
        guard projected.count >= 3 else {
            return Path()
        }
        var path = Path()
        path.move(to: projected[0])
        for point in projected.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    /// Check if a face is front-facing (visible to camera).
    func isFrontFacing(vertices: [SIMD3<Float>], modelMatrix: float4x4 = .identity) -> Bool {
        guard vertices.count >= 3 else {
            return false
        }
        let mv = viewMatrix * modelMatrix
        let viewVerts = vertices.map { v -> SIMD3<Float> in
            let transformed = mv * SIMD4(v, 1)
            return transformed.xyz / transformed.w
        }
        let edge0 = viewVerts[1] - viewVerts[0]
        let edge1 = viewVerts[2] - viewVerts[0]
        let normal = simd_cross(edge0, edge1)
        let centroid = viewVerts.reduce(.zero, +) / Float(viewVerts.count)
        return simd_dot(normal, -centroid) > 0
    }
}

// MARK: - Mesh rendering into Canvas

extension Mesh {
    /// Draw the mesh into a SwiftUI GraphicsContext using a software renderer.
    func draw(
        in context: inout GraphicsContext,
        renderer: SoftwareRenderer,
        modelMatrix: float4x4 = .identity,
        fillColor: Color = .blue,
        strokeColor: Color = .white,
        lineWidth: CGFloat = 1,
        backfaceCull: Bool = true
    ) {
        // Collect faces with depth for painter's algorithm sorting
        struct FaceDrawInfo {
            var path: Path
            var depth: Float
            var isFront: Bool
            var normal: SIMD3<Float>
        }

        var drawInfos: [FaceDrawInfo] = []

        for face in topology.faces {
            let vertexIDs = topology.vertexLoop(for: face.id)
            let pts = vertexIDs.map { positions[$0.raw] }

            let isFront = renderer.isFrontFacing(vertices: pts, modelMatrix: modelMatrix)
            if backfaceCull, !isFront {
                continue
            }

            let path = renderer.path(for: pts, modelMatrix: modelMatrix)

            // Depth = average Z in view space for sorting
            let mv = renderer.viewMatrix * modelMatrix
            let avgZ = pts.reduce(Float(0)) { sum, pt in
                let transformed = mv * SIMD4(pt, 1)
                return sum + transformed.z / transformed.w
            } / Float(pts.count)

            let faceNormal = self.faceNormal(face.id)

            drawInfos.append(FaceDrawInfo(path: path, depth: avgZ, isFront: isFront, normal: faceNormal))
        }

        // Sort back-to-front (most negative Z first = farthest)
        drawInfos.sort { $0.depth < $1.depth }

        // Draw
        for info in drawInfos {
            // Simple directional lighting
            let lightDir = simd_normalize(SIMD3<Float>(0.3, 1.0, 0.5))
            let modelNormal = simd_normalize((modelMatrix.upperLeft3x3 * info.normal))
            let brightness = max(0.15, simd_dot(modelNormal, lightDir))

            let shadedColor = fillColor.opacity(Double(brightness))
            context.fill(info.path, with: .color(shadedColor))
            context.stroke(info.path, with: .color(strokeColor.opacity(0.3)), lineWidth: lineWidth)
        }
    }
}
