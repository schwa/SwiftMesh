import GeometryLite3D
import Metal
import MetalSupport
import simd

public extension MetalMesh {
    /// A copy with positions, normals, tangents and bitangents transformed by `matrix`.
    ///
    /// Vertex data is read back, transformed on the CPU, and uploaded to new buffers on the same
    /// device; the source buffers must be CPU-visible. Normals use the inverse transpose; tangent
    /// handedness (w of a `.float4` tangent) is kept. Other attributes, morph targets and skin are
    /// copied unchanged. Index buffers are rebuilt as `.uint32`.
    func transformed(by matrix: simd_float4x4) -> MetalMesh {
        guard let device = vertexBuffers.values.first?.device else {
            return self
        }
        let upperLeft = matrix.upperLeft3x3
        let normalMatrix = abs(upperLeft.determinant) > 1e-8 ? upperLeft.inverse.transpose : upperLeft

        let attributes = vertexAttributeData().map { data -> VertexAttributeData in
            switch data.semantic {
            case .position:
                return data.mappingXYZ { (matrix * SIMD4($0, 1)).xyz }

            case .normal:
                return data.mappingXYZ { Self.normalized(normalMatrix * $0) }

            case .tangent, .bitangent:
                return data.mappingXYZ { Self.normalized(upperLeft * $0) }

            default:
                return data
            }
        }
        let submeshIndices = submeshes.map { SubmeshIndices(label: $0.label, indices: $0.indices, primitiveType: $0.primitiveType) }
        let interleaved = Set(vertexDescriptor.attributes.map(\.bufferIndex)).count <= 1
        var result = MetalMesh(
            device: device,
            attributes: attributes,
            submeshes: submeshIndices,
            morphTargets: morphTargets,
            skin: skin,
            label: label,
            bufferLayout: interleaved ? .interleaved : .separateBuffers
        )
        result.opposites = opposites
        result.vertToHalfedge = vertToHalfedge
        return result
    }

    private static func normalized(_ value: SIMD3<Float>) -> SIMD3<Float> {
        let length = simd_length(value)
        return length > 0 ? value / length : value
    }
}

private extension MetalMesh.VertexAttributeData {
    /// Applies `transform` to the xyz of each `.float3` or `.float4` value, keeping w.
    /// Other formats are returned unchanged.
    func mappingXYZ(_ transform: (SIMD3<Float>) -> SIMD3<Float>) -> Self {
        switch format {
        case .float3:
            let values: [SIMD3<Float>] = values()
            return Self(semantic: semantic, format: format, values: values.map(transform))

        case .float4:
            let values: [SIMD4<Float>] = values()
            return Self(semantic: semantic, format: format, values: values.map { SIMD4(transform($0.xyz), $0.w) })

        default:
            return self
        }
    }
}
