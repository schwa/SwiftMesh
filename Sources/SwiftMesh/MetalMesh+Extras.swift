import GeometryLite3D
import Metal
import MetalSupport
import simd

// MARK: - Morph targets

public extension MetalMesh {
    /// Per-vertex offsets that a renderer blends onto the base vertices by weight.
    ///
    /// The weights for each frame are animation state and are not stored here.
    struct MorphTargets {
        /// One morph target. Each non-nil array has one offset per vertex of the mesh.
        public struct Target {
            public var label: String?
            public var positionOffsets: [SIMD3<Float>]?
            public var normalOffsets: [SIMD3<Float>]?
            public var tangentOffsets: [SIMD3<Float>]?

            public init(label: String? = nil, positionOffsets: [SIMD3<Float>]? = nil, normalOffsets: [SIMD3<Float>]? = nil, tangentOffsets: [SIMD3<Float>]? = nil) {
                self.label = label
                self.positionOffsets = positionOffsets
                self.normalOffsets = normalOffsets
                self.tangentOffsets = tangentOffsets
            }
        }

        public var targets: [Target]
        /// Weights to use when no animation sets them. Empty means all zero.
        public var defaultWeights: [Float]

        public init(targets: [Target], defaultWeights: [Float] = []) {
            precondition(defaultWeights.isEmpty || defaultWeights.count == targets.count, "defaultWeights.count must equal targets.count")
            self.targets = targets
            self.defaultWeights = defaultWeights
        }
    }
}

// MARK: - Skin

public extension MetalMesh {
    /// The joint list that the `.jointIndices` vertex attributes index into.
    ///
    /// Which scene nodes act as the joints, and their matrices for each frame, are model state and are not stored here.
    struct Skin {
        /// One inverse bind matrix per joint, in joint order.
        public var inverseBindMatrices: [simd_float4x4]
        /// Optional joint names, in joint order.
        public var jointNames: [String]?

        public var jointCount: Int { inverseBindMatrices.count }

        public init(inverseBindMatrices: [simd_float4x4], jointNames: [String]? = nil) {
            if let jointNames { precondition(jointNames.count == inverseBindMatrices.count, "jointNames.count must equal inverseBindMatrices.count") }
            self.inverseBindMatrices = inverseBindMatrices
            self.jointNames = jointNames
        }
    }
}

// MARK: - Bounds

public extension MetalMesh {
    /// Recomputes ``bounds`` and each submesh's bounds by reading the position attribute.
    ///
    /// The vertex and index buffers must be CPU accessible.
    mutating func updateBounds() {
        guard let attribute = vertexDescriptor.attributes.first(where: { $0.semantic == .position }), attribute.format == .float3,
              let buffer = vertexBuffers[attribute.bufferIndex], let stride = vertexDescriptor.layouts[attribute.bufferIndex]?.stride
        else {
            bounds = nil
            return
        }
        let base = buffer.contents() + (vertexBufferOffsets[attribute.bufferIndex] ?? 0) + attribute.offset
        let positions = (0..<vertexCount).map { index in
            let pointer = base + index * stride
            return SIMD3(pointer.loadUnaligned(as: Float.self), pointer.loadUnaligned(fromByteOffset: 4, as: Float.self), pointer.loadUnaligned(fromByteOffset: 8, as: Float.self))
        }
        bounds = Self.bounds(of: positions)
        for index in submeshes.indices {
            submeshes[index].bounds = Self.bounds(of: positions, indices: submeshes[index].indices)
        }
    }

    internal static func bounds(of positions: [SIMD3<Float>]) -> BoundingBox3D? {
        guard let first = positions.first else { return nil }
        var box = BoundingBox3D(min: first, max: first)
        for position in positions {
            box.min = simd.min(box.min, position)
            box.max = simd.max(box.max, position)
        }
        return box
    }

    internal static func bounds(of positions: [SIMD3<Float>], indices: [UInt32]) -> BoundingBox3D? {
        guard let first = indices.first else { return nil }
        var box = BoundingBox3D(min: positions[Int(first)], max: positions[Int(first)])
        for index in indices {
            box.min = simd.min(box.min, positions[Int(index)])
            box.max = simd.max(box.max, positions[Int(index)])
        }
        return box
    }
}
