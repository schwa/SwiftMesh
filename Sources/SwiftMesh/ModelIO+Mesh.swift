import Metal
import MetalKit
import MetalSupport
import ModelIO
import simd

/// Errors that can occur during ModelIO conversion.
public enum ModelIOConversionError: Error {
    case bufferCreationFailed
}

// MARK: - MDLMesh → Mesh

public extension Mesh {
    /// Create a Mesh from a ModelIO mesh.
    ///
    /// Internally converts via MTKMesh → MetalMesh → Mesh.
    /// The resulting mesh is triangle-only with per-corner attributes preserved.
    init(mdlMesh: MDLMesh, device: MTLDevice) throws {
        // Ensure the MDL mesh has a suitable vertex descriptor for Metal
        let mdlDescriptor = mdlMesh.vertexDescriptor
        Self.ensurePackedLayout(mdlDescriptor)

        let mtkMesh = try MTKMesh(mesh: mdlMesh, device: device)
        let metalMesh = try MetalMesh(mtkMesh: mtkMesh)
        self = metalMesh.toMesh()
    }

    /// Ensure all MDL vertex attributes have packed offsets and strides.
    private static func ensurePackedLayout(_ descriptor: MDLVertexDescriptor) {
        // MDL sometimes has zero strides — fix by calling makePacked
        descriptor.setPackedOffsets()
        descriptor.setPackedStrides()
    }
}

// MARK: - MetalMesh from MTKMesh

public extension MetalMesh {
    /// Create a MetalMesh from an MTKMesh.
    ///
    /// Maps MTKMesh's vertex buffers, vertex descriptor, and submeshes
    /// into MetalMesh's representation.
    init(mtkMesh: MTKMesh) {
        self.label = mtkMesh.name.isEmpty ? nil : mtkMesh.name

        // Map the MDL vertex descriptor to our VertexDescriptor
        let mdlDescriptor = mtkMesh.vertexDescriptor
        var attributes: [VertexDescriptor.Attribute] = []

        // Map known MDL attribute names to our semantics
        let semanticMap: [String: VertexDescriptor.Attribute.Semantic] = [
            MDLVertexAttributePosition: .position,
            MDLVertexAttributeNormal: .normal,
            MDLVertexAttributeTextureCoordinate: .texcoord(),
            MDLVertexAttributeTangent: .tangent,
            MDLVertexAttributeBitangent: .bitangent,
            MDLVertexAttributeColor: .color()
        ]

        for mdlAttr in mdlDescriptor.attributes as! [MDLVertexAttribute] {
            guard mdlAttr.format != .invalid else { continue }
            let semantic = semanticMap[mdlAttr.name] ?? .userDefined
            guard let mtlFormat = Self.mdlToMTLFormat(mdlAttr.format) else { continue }

            attributes.append(.init(
                semantic: semantic,
                format: mtlFormat,
                offset: mdlAttr.offset,
                bufferIndex: mdlAttr.bufferIndex
            ))
        }

        // Build layouts from MDL layouts
        var layouts: [VertexDescriptor.Layout] = []
        for (idx, mdlLayout) in (mdlDescriptor.layouts as! [MDLVertexBufferLayout]).enumerated() {
            guard mdlLayout.stride > 0 else { continue }
            layouts.append(.init(
                bufferIndex: idx,
                stride: mdlLayout.stride,
                stepFunction: .perVertex,
                stepRate: 1
            ))
        }

        self.vertexDescriptor = VertexDescriptor(attributes: attributes, layouts: layouts)
        self.vertexCount = mtkMesh.vertexCount

        // Map vertex buffers
        var vtxBuffers: [Int: MTLBuffer] = [:]
        var offsets: [Int: Int] = [:]
        for (idx, mtkBuffer) in mtkMesh.vertexBuffers.enumerated() {
            vtxBuffers[idx] = mtkBuffer.buffer
            if mtkBuffer.offset != 0 {
                offsets[idx] = mtkBuffer.offset
            }
        }
        self.vertexBuffers = vtxBuffers
        self.vertexBufferOffsets = offsets

        self.submeshes = mtkMesh.submeshes.map { sub in
            Submesh(
                label: sub.name.isEmpty ? nil : sub.name,
                indexBuffer: sub.indexBuffer.buffer,
                indexBufferOffset: sub.indexBuffer.offset,
                indexCount: sub.indexCount,
                indexType: sub.indexType,
                primitiveType: sub.primitiveType
            )
        }
    }

    /// Convert an MDLVertexFormat to the equivalent MTLVertexFormat.
    private static func mdlToMTLFormat(_ format: MDLVertexFormat) -> MTLVertexFormat? {
        switch format {
        case .float2: return .float2
        case .float3: return .float3
        case .float4: return .float4
        case .half2: return .half2
        case .half3: return .half3
        case .half4: return .half4
        case .int: return .int
        case .int2: return .int2
        case .int3: return .int3
        case .int4: return .int4
        case .uInt: return .uint
        case .uInt2: return .uint2
        case .uInt3: return .uint3
        case .uInt4: return .uint4
        case .char2: return .char2
        case .char3: return .char3
        case .char4: return .char4
        case .uChar2: return .uchar2
        case .uChar3: return .uchar3
        case .uChar4: return .uchar4
        case .char2Normalized: return .char2Normalized
        case .char3Normalized: return .char3Normalized
        case .char4Normalized: return .char4Normalized
        case .uChar2Normalized: return .uchar2Normalized
        case .uChar3Normalized: return .uchar3Normalized
        case .uChar4Normalized: return .uchar4Normalized
        case .short2: return .short2
        case .short3: return .short3
        case .short4: return .short4
        case .uShort2: return .ushort2
        case .uShort3: return .ushort3
        case .uShort4: return .ushort4
        case .short2Normalized: return .short2Normalized
        case .short3Normalized: return .short3Normalized
        case .short4Normalized: return .short4Normalized
        case .uShort2Normalized: return .ushort2Normalized
        case .uShort3Normalized: return .ushort3Normalized
        case .uShort4Normalized: return .ushort4Normalized
        default: return nil
        }
    }
}

// MARK: - MDLAsset → [Mesh]

public extension Array where Element == Mesh {
    /// Convert every MDLMesh in an asset into a Mesh, one per source mesh.
    ///
    /// Order matches a depth-first walk of the asset's object graph. The caller
    /// decides what to do with the result (render separately, `Mesh.merged(_:)`, ...).
    ///
    /// - Parameter applyingTransforms: Bake each mesh's world transform (its own
    ///   and its ancestors') into positions and directions. Set `false` to keep
    ///   meshes in their local space.
    init(mdlAsset: MDLAsset, device: MTLDevice, applyingTransforms: Bool = true) throws {
        var meshes: [Mesh] = []
        func visit(_ object: MDLObject) throws {
            if let mdlMesh = object as? MDLMesh {
                var mesh = try Mesh(mdlMesh: mdlMesh, device: device)
                if applyingTransforms {
                    let transform = MDLTransform.globalTransform(with: object, atTime: 0)
                    if transform != matrix_identity_float4x4 {
                        mesh.transform(by: transform)
                    }
                }
                meshes.append(mesh)
            }
            for child in object.children.objects {
                try visit(child)
            }
        }
        for index in 0..<mdlAsset.count {
            try visit(mdlAsset.object(at: index))
        }
        self = meshes
    }
}

// MARK: - Mesh → MDLMesh

public extension Mesh {
    /// Convert to a ModelIO mesh.
    ///
    /// Triangulates faces and packs positions, normals, and UVs into MDL vertex buffers.
    func toMDLMesh(device: MTLDevice) -> MDLMesh {
        let allocator = MTKMeshBufferAllocator(device: device)

        // Build a MetalMesh (interleaved) then extract the data
        let metalMesh = MetalMesh(mesh: self, device: device, bufferLayout: .interleaved)

        // Create MDL vertex descriptor from our descriptor
        let mdlDescriptor = MDLVertexDescriptor()

        let semanticToName: [VertexDescriptor.Attribute.Semantic: String] = [
            .position: MDLVertexAttributePosition,
            .normal: MDLVertexAttributeNormal,
            .texcoord(): MDLVertexAttributeTextureCoordinate,
            .tangent: MDLVertexAttributeTangent,
            .bitangent: MDLVertexAttributeBitangent,
            .color(): MDLVertexAttributeColor
        ]

        for (idx, attr) in metalMesh.vertexDescriptor.attributes.enumerated() {
            let mdlAttr = mdlDescriptor.attributes[idx] as! MDLVertexAttribute
            mdlAttr.name = semanticToName[attr.semantic] ?? "attribute_\(idx)"
            mdlAttr.format = Self.mtlToMDLFormat(attr.format)
            mdlAttr.offset = attr.offset
            mdlAttr.bufferIndex = attr.bufferIndex
        }

        let stride = metalMesh.vertexDescriptor.layouts[0]!.stride
        let mdlLayout = mdlDescriptor.layouts[0] as! MDLVertexBufferLayout
        mdlLayout.stride = stride

        // Create vertex buffer via allocator
        let vertexBuffer = metalMesh.vertexBuffers[0]!
        let vertexData = Data(bytes: vertexBuffer.contents() + (metalMesh.vertexBufferOffsets[0] ?? 0), count: metalMesh.vertexCount * stride)
        let mdlVertexBuffer = allocator.newBuffer(with: vertexData, type: .vertex)

        // Build submeshes
        var mdlSubmeshes: [MDLSubmesh] = []
        for submesh in metalMesh.submeshes {
            let is16Bit = submesh.indexType == .uint16
            let indexData = Data(
                bytes: submesh.indexBuffer.contents() + submesh.indexBufferOffset,
                count: submesh.indexByteCount
            )
            let mdlIndexBuffer = allocator.newBuffer(with: indexData, type: .index)
            let geometryType: MDLGeometryType = switch submesh.primitiveType {
            case .point: .points
            case .line: .lines
            case .triangleStrip: .triangleStrips
            default: .triangles
            }
            let mdlSubmesh = MDLSubmesh(
                name: submesh.label ?? "",
                indexBuffer: mdlIndexBuffer,
                indexCount: submesh.indexCount,
                indexType: is16Bit ? .uInt16 : .uInt32,
                geometryType: geometryType,
                material: nil
            )
            mdlSubmeshes.append(mdlSubmesh)
        }

        return MDLMesh(
            vertexBuffer: mdlVertexBuffer,
            vertexCount: metalMesh.vertexCount,
            descriptor: mdlDescriptor,
            submeshes: mdlSubmeshes
        )
    }

    /// Convert an MTLVertexFormat to the equivalent MDLVertexFormat.
    private static func mtlToMDLFormat(_ format: MTLVertexFormat) -> MDLVertexFormat {
        switch format {
        case .float2: return .float2
        case .float3: return .float3
        case .float4: return .float4
        case .half2: return .half2
        case .half3: return .half3
        case .half4: return .half4
        case .int: return .int
        case .int2: return .int2
        case .int3: return .int3
        case .int4: return .int4
        case .uint: return .uInt
        case .uint2: return .uInt2
        case .uint3: return .uInt3
        case .uint4: return .uInt4
        case .char2: return .char2
        case .char3: return .char3
        case .char4: return .char4
        case .uchar2: return .uChar2
        case .uchar3: return .uChar3
        case .uchar4: return .uChar4
        case .char2Normalized: return .char2Normalized
        case .char3Normalized: return .char3Normalized
        case .char4Normalized: return .char4Normalized
        case .uchar2Normalized: return .uChar2Normalized
        case .uchar3Normalized: return .uChar3Normalized
        case .uchar4Normalized: return .uChar4Normalized
        case .short2: return .short2
        case .short3: return .short3
        case .short4: return .short4
        case .ushort2: return .uShort2
        case .ushort3: return .uShort3
        case .ushort4: return .uShort4
        case .short2Normalized: return .short2Normalized
        case .short3Normalized: return .short3Normalized
        case .short4Normalized: return .short4Normalized
        case .ushort2Normalized: return .uShort2Normalized
        case .ushort3Normalized: return .uShort3Normalized
        case .ushort4Normalized: return .uShort4Normalized
        default: return .invalid
        }
    }
}
