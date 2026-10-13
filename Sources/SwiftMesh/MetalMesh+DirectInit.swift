import GeometryLite3D
import Metal
import MetalSupport
import simd

// MARK: - Direct initializers (bypass Mesh / topology)

public extension MetalMesh {
    /// One per-vertex attribute array, packed to `format`.
    struct VertexAttributeData {
        public var semantic: VertexDescriptor.Attribute.Semantic
        public var format: MTLVertexFormat
        /// `count * format.size` bytes, tightly packed.
        public var bytes: [UInt8]
        public var count: Int

        /// Copies the first `format.size` bytes of each value.
        public init<Element>(semantic: VertexDescriptor.Attribute.Semantic, format: MTLVertexFormat, values: [Element]) {
            let size = format.size
            precondition(size > 0 && MemoryLayout<Element>.size >= size, "\(Element.self) is too small for format \(format)")
            var bytes = [UInt8](repeating: 0, count: size * values.count)
            bytes.withUnsafeMutableBytes { destination in
                values.withUnsafeBytes { source in
                    for index in values.indices {
                        (destination.baseAddress! + index * size).copyMemory(from: source.baseAddress! + index * MemoryLayout<Element>.stride, byteCount: size)
                    }
                }
            }
            self.semantic = semantic
            self.format = format
            self.bytes = bytes
            self.count = values.count
        }

        public static func positions(_ values: [SIMD3<Float>]) -> Self {
            .init(semantic: .position, format: .float3, values: values)
        }

        public static func normals(_ values: [SIMD3<Float>]) -> Self {
            .init(semantic: .normal, format: .float3, values: values)
        }

        public static func textureCoordinates(_ values: [SIMD2<Float>], set: Int = 0) -> Self {
            .init(semantic: .texcoord(set), format: .float2, values: values)
        }

        /// glTF-style tangents: xyz plus handedness in w.
        public static func tangents(_ values: [SIMD4<Float>]) -> Self {
            .init(semantic: .tangent, format: .float4, values: values)
        }

        public static func tangents(_ values: [SIMD3<Float>]) -> Self {
            .init(semantic: .tangent, format: .float3, values: values)
        }

        public static func bitangents(_ values: [SIMD3<Float>]) -> Self {
            .init(semantic: .bitangent, format: .float3, values: values)
        }

        public static func colors(_ values: [SIMD4<Float>], set: Int = 0) -> Self {
            .init(semantic: .color(set), format: .float4, values: values)
        }

        public static func jointIndices(_ values: [SIMD4<UInt16>], set: Int = 0) -> Self {
            .init(semantic: .jointIndices(set), format: .ushort4, values: values)
        }

        public static func jointWeights(_ values: [SIMD4<Float>], set: Int = 0) -> Self {
            .init(semantic: .jointWeights(set), format: .float4, values: values)
        }
    }

    /// The indices of one submesh for the array initializer.
    struct SubmeshIndices {
        public var label: String?
        public var indices: [UInt32]
        public var primitiveType: MTLPrimitiveType

        public init(label: String? = nil, indices: [UInt32], primitiveType: MTLPrimitiveType = .triangle) {
            self.label = label
            self.indices = indices
            self.primitiveType = primitiveType
        }
    }

    /// Create a `MetalMesh` from in-memory attribute arrays, skipping the half-edge topology pipeline.
    ///
    /// `attributes` must contain a `.position` attribute in `.float3` format, and all attributes must have the same count.
    /// Attributes keep their order in the vertex descriptor. Each submesh gets its own index buffer; use
    /// ``mergingIndexBuffers()`` to share one.
    init(
        device: MTLDevice,
        attributes: [VertexAttributeData],
        submeshes: [SubmeshIndices],
        morphTargets: MorphTargets? = nil,
        skin: Skin? = nil,
        label: String? = nil,
        bufferLayout: BufferLayout = .interleaved
    ) {
        guard let positionData = attributes.first(where: { $0.semantic == .position }), positionData.format == .float3 else {
            preconditionFailure("attributes must contain a .float3 .position attribute")
        }
        let vertexCount = positionData.count
        for attribute in attributes {
            precondition(attribute.count == vertexCount, "attribute \(attribute.semantic) count must equal the position count")
        }

        let descriptorAttributes: [VertexDescriptor.Attribute]
        let layouts: [VertexDescriptor.Layout]
        switch bufferLayout {
        case .interleaved:
            descriptorAttributes = attributes.map {
                VertexDescriptor.Attribute(semantic: $0.semantic, format: $0.format, offset: 0, bufferIndex: 0)
            }
            layouts = [.init(bufferIndex: 0, stride: 0, stepFunction: .perVertex, stepRate: 1)]

        case .separateBuffers:
            descriptorAttributes = attributes.enumerated().map { index, attribute in
                VertexDescriptor.Attribute(semantic: attribute.semantic, format: attribute.format, offset: 0, bufferIndex: index)
            }
            layouts = attributes.indices.map {
                .init(bufferIndex: $0, stride: 0, stepFunction: .perVertex, stepRate: 1)
            }
        }
        let descriptor = VertexDescriptor(attributes: descriptorAttributes, layouts: layouts).normalized()

        var vertexBuffers: [Int: MTLBuffer] = [:]
        for bufferIndex in Set(descriptor.attributes.map(\.bufferIndex)).sorted() {
            let stride = descriptor.layouts[bufferIndex]!.stride
            var data = [UInt8](repeating: 0, count: stride * vertexCount)
            data.withUnsafeMutableBytes { destination in
                for (attribute, source) in zip(descriptor.attributes, attributes) where attribute.bufferIndex == bufferIndex {
                    let size = attribute.format.size
                    source.bytes.withUnsafeBytes { sourceBytes in
                        for vertex in 0..<vertexCount {
                            (destination.baseAddress! + vertex * stride + attribute.offset).copyMemory(from: sourceBytes.baseAddress! + vertex * size, byteCount: size)
                        }
                    }
                }
            }
            let buffer = data.isEmpty ? device.makeBuffer(length: 1, options: [])! : device.makeBuffer(bytes: data, length: data.count, options: [])!
            buffer.label = label.map { "\($0) Vertices[\(bufferIndex)]" }
            vertexBuffers[bufferIndex] = buffer
        }

        let positions: [SIMD3<Float>] = positionData.bytes.withUnsafeBytes { bytes in
            (0..<vertexCount).map { index in
                SIMD3(bytes.loadUnaligned(fromByteOffset: index * 12, as: Float.self), bytes.loadUnaligned(fromByteOffset: index * 12 + 4, as: Float.self), bytes.loadUnaligned(fromByteOffset: index * 12 + 8, as: Float.self))
            }
        }

        let builtSubmeshes = submeshes.map { submesh in
            let indexBuffer = device.makeBuffer(bytes: submesh.indices, length: max(1, MemoryLayout<UInt32>.stride * submesh.indices.count), options: [])!
            indexBuffer.label = submesh.label ?? label.map { "\($0) Indices" }
            return Submesh(label: submesh.label, indexBuffer: indexBuffer, indexCount: submesh.indices.count, primitiveType: submesh.primitiveType, bounds: Self.bounds(of: positions, indices: submesh.indices))
        }

        self.label = label
        self.vertexBuffers = vertexBuffers
        self.vertexCount = vertexCount
        self.vertexDescriptor = descriptor
        self.submeshes = builtSubmeshes
        self.bounds = Self.bounds(of: positions)
        self.morphTargets = morphTargets
        self.skin = skin
    }

    /// Create a `MetalMesh` from in-memory attribute arrays with a single triangle submesh.
    init(
        device: MTLDevice,
        positions: [SIMD3<Float>],
        normals: [SIMD3<Float>]? = nil,
        textureCoordinates: [SIMD2<Float>]? = nil,
        indices: [UInt32],
        label: String? = nil,
        bufferLayout: BufferLayout = .interleaved
    ) {
        var attributes: [VertexAttributeData] = [.positions(positions)]
        if let normals { attributes.append(.normals(normals)) }
        if let textureCoordinates { attributes.append(.textureCoordinates(textureCoordinates)) }
        self.init(device: device, attributes: attributes, submeshes: [SubmeshIndices(indices: indices)], label: label, bufferLayout: bufferLayout)
    }

    /// Create a `MetalMesh` from existing buffers and a matching `VertexDescriptor`, with no copies.
    ///
    /// Only cheap shape checks are performed. ``bounds`` is left nil; call ``updateBounds()`` if the buffers are CPU accessible.
    init(
        vertexBuffers: [Int: MTLBuffer],
        vertexBufferOffsets: [Int: Int] = [:],
        vertexCount: Int,
        vertexDescriptor: VertexDescriptor,
        submeshes: [Submesh],
        label: String? = nil
    ) {
        for bufferIndex in Set(vertexDescriptor.attributes.map(\.bufferIndex)) {
            precondition(vertexBuffers[bufferIndex] != nil, "vertexBuffers is missing buffer at index \(bufferIndex) referenced by vertexDescriptor")
        }

        self.label = label
        self.vertexBuffers = vertexBuffers
        self.vertexBufferOffsets = vertexBufferOffsets
        self.vertexCount = vertexCount
        self.vertexDescriptor = vertexDescriptor
        self.submeshes = submeshes
    }

    /// Create a `MetalMesh` from existing buffers with a single submesh covering all indices.
    init(
        vertexBuffers: [Int: MTLBuffer],
        vertexBufferOffsets: [Int: Int] = [:],
        vertexCount: Int,
        vertexDescriptor: VertexDescriptor,
        indexBuffer: MTLBuffer,
        indexBufferOffset: Int = 0,
        indexCount: Int,
        indexType: MTLIndexType = .uint32,
        primitiveType: MTLPrimitiveType = .triangle,
        label: String? = nil
    ) {
        self.init(
            vertexBuffers: vertexBuffers,
            vertexBufferOffsets: vertexBufferOffsets,
            vertexCount: vertexCount,
            vertexDescriptor: vertexDescriptor,
            submeshes: [Submesh(indexBuffer: indexBuffer, indexBufferOffset: indexBufferOffset, indexCount: indexCount, indexType: indexType, primitiveType: primitiveType)],
            label: label
        )
    }
}
