import GeometryLite3D
import Metal
import MetalSupport
import simd

/// A GPU-ready mesh produced from a `Mesh` by triangulating faces,
/// splitting vertices per-corner, and interleaving attributes into Metal buffers.
///
/// Currently assumes all faces are triangles. N-gon triangulation (fan/earcut)
/// will be added later.
public struct MetalMesh {

    public struct Submesh {
        public var label: String?
        public var materialIndex: Int
        public var indexBuffer: MTLBuffer
        public var indexCount: Int
    }

    public var label: String?
    public var vertexBuffer: MTLBuffer
    public var vertexCount: Int
    public var vertexDescriptor: VertexDescriptor
    public var submeshes: [Submesh]

    /// Create a MetalMesh from a Mesh.
    ///
    /// Each half-edge corner becomes a unique vertex in the output buffer.
    /// Faces are grouped by material tag into submeshes.
    /// Currently only supports triangle faces.
    public init(mesh: Mesh, device: MTLDevice, label: String? = nil) {
        self.label = label

        // Build vertex descriptor based on available attributes
        var attributes: [VertexDescriptor.Attribute] = [
            .init(semantic: .position, format: .float3, offset: 0, bufferIndex: 0)
        ]
        if mesh.normals != nil {
            attributes.append(.init(semantic: .normal, format: .float3, offset: 0, bufferIndex: 0))
        }
        if mesh.textureCoordinates != nil {
            attributes.append(.init(semantic: .texcoord, format: .float2, offset: 0, bufferIndex: 0))
        }
        if mesh.colors != nil {
            attributes.append(.init(semantic: .color, format: .float4, offset: 0, bufferIndex: 0))
        }

        let descriptor = VertexDescriptor(
            attributes: attributes,
            layouts: [.init(bufferIndex: 0, stride: 0, stepFunction: .perVertex, stepRate: 1)]
        ).normalized()

        self.vertexDescriptor = descriptor

        let stride = descriptor.layouts[0]!.stride

        // Group faces by material
        var facesByMaterial: [Int: [HalfEdgeTopology.FaceID]] = [:]
        for face in mesh.topology.faces {
            let mat = mesh.faceMaterial(face.id)
            facesByMaterial[mat, default: []].append(face.id)
        }

        // Walk all faces to build interleaved vertex data and per-material index arrays
        var vertexData = [UInt8]()
        var currentVertexIndex: UInt32 = 0
        var submeshIndices: [Int: [UInt32]] = [:]

        for (mat, faceIDs) in facesByMaterial.sorted(by: { $0.key < $1.key }) {
            var indices: [UInt32] = []

            for faceID in faceIDs {
                let heLoop = mesh.topology.halfEdgeLoop(for: faceID)
                // Currently assumes triangles
                assert(heLoop.count == 3, "MetalMesh currently only supports triangle faces (got \(heLoop.count)-gon)")

                for heID in heLoop {
                    let vertexID = mesh.topology.halfEdges[heID.raw].origin

                    // Write interleaved vertex
                    var vertexBytes = [UInt8](repeating: 0, count: stride)
                    vertexBytes.withUnsafeMutableBytes { bytes in
                        guard let base = bytes.baseAddress else {
                            return
                        }
                        for attr in descriptor.attributes where attr.bufferIndex == 0 {
                            let dest = base.advanced(by: attr.offset)
                            switch attr.semantic {
                            case .position:
                                var packed = Packed3<Float>(mesh.positions[vertexID.raw])
                                withUnsafeBytes(of: &packed) { src in
                                    dest.copyMemory(from: src.baseAddress!, byteCount: src.count)
                                }
                            case .normal:
                                if let normals = mesh.normals {
                                    var packed = Packed3<Float>(normals[heID.raw])
                                    withUnsafeBytes(of: &packed) { src in
                                        dest.copyMemory(from: src.baseAddress!, byteCount: src.count)
                                    }
                                }
                            case .texcoord:
                                if let uvs = mesh.textureCoordinates {
                                    var uv = uvs[heID.raw]
                                    withUnsafeBytes(of: &uv) { src in
                                        dest.copyMemory(from: src.baseAddress!, byteCount: src.count)
                                    }
                                }
                            case .color:
                                if let colors = mesh.colors {
                                    var color = colors[heID.raw]
                                    withUnsafeBytes(of: &color) { src in
                                        dest.copyMemory(from: src.baseAddress!, byteCount: src.count)
                                    }
                                }
                            default:
                                break
                            }
                        }
                    }

                    vertexData.append(contentsOf: vertexBytes)
                    indices.append(currentVertexIndex)
                    currentVertexIndex += 1
                }
            }

            submeshIndices[mat] = indices
        }

        self.vertexCount = Int(currentVertexIndex)

        // Create vertex buffer
        let vtxBuffer: MTLBuffer
        if vertexData.isEmpty {
            vtxBuffer = device.makeBuffer(length: 1, options: [])!
        } else {
            vtxBuffer = device.makeBuffer(bytes: vertexData, length: vertexData.count, options: [])!
        }
        vtxBuffer.label = label.map { "\($0) Vertices" }
        self.vertexBuffer = vtxBuffer

        // Create submeshes
        self.submeshes = submeshIndices.sorted(by: { $0.key < $1.key }).map { mat, indices in
            let idxBuffer = device.makeBuffer(
                bytes: indices,
                length: MemoryLayout<UInt32>.stride * indices.count,
                options: []
            )!
            idxBuffer.label = label.map { "\($0) Indices [material \(mat)]" }
            return Submesh(
                label: label,
                materialIndex: mat,
                indexBuffer: idxBuffer,
                indexCount: indices.count
            )
        }
    }
}

// MARK: - Drawing

public extension MTLRenderCommandEncoder {
    func draw(_ metalMesh: MetalMesh) {
        setVertexBuffer(metalMesh.vertexBuffer, offset: 0, index: 0)
        for submesh in metalMesh.submeshes {
            drawIndexedPrimitives(
                type: .triangle,
                indexCount: submesh.indexCount,
                indexType: .uint32,
                indexBuffer: submesh.indexBuffer,
                indexBufferOffset: 0
            )
        }
    }
}
