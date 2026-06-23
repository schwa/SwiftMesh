import Foundation
import RealityKit
import simd
import SwiftMesh

// MARK: - Errors

public enum MeshResourceConversionError: Error, CustomStringConvertible {
    case emptyMesh
    case invalidMesh([ValidationIssue])
    case generationFailed(any Error)

    public var description: String {
        switch self {
        case .emptyMesh:
            "Cannot convert an empty mesh to MeshResource."

        case .invalidMesh(let issues):
            "Mesh failed validation: \(issues.map(\.message).joined(separator: "; "))"

        case .generationFailed(let underlying):
            "RealityKit MeshResource.generate failed: \(underlying)"
        }
    }
}

// MARK: - MeshResource conversion

public extension MeshResource {
    /// Convert a SwiftMesh ``Mesh`` into a `MeshResource`.
    ///
    /// Each ``Mesh/Submesh`` becomes a separate `MeshResource.Part` within a
    /// single `MeshResource.Model`, preserving its label as the part's `id`
    /// (falling back to `"submesh_<index>"` when the label is `nil`).
    ///
    /// SwiftMesh stores normals, texture coordinates, tangents, and colors
    /// per half-edge corner, while RealityKit needs per-vertex arrays. Where
    /// corners that share a position have differing attributes (sharp edges,
    /// UV seams), vertices are duplicated so each corner gets its own slot.
    ///
    /// N-gons are triangulated via SwiftMesh's earcut-based ``Mesh/triangulate()``.
    ///
    /// - Parameters:
    ///   - mesh: The SwiftMesh mesh to convert.
    ///   - generateTangentsIfMissing: When `true`, derive tangents via MikkTSpace
    ///     if the source mesh has normals and UVs but no tangents.
    /// - Returns: A new `MeshResource` ready to use with `ModelEntity`.
    @MainActor
    static func generate(from mesh: Mesh, generateTangentsIfMissing: Bool = true) throws -> MeshResource {
        guard !mesh.positions.isEmpty, !mesh.submeshes.isEmpty else {
            throw MeshResourceConversionError.emptyMesh
        }

        let validationIssues = mesh.validate().filter { $0.severity == .error }
        if !validationIssues.isEmpty {
            throw MeshResourceConversionError.invalidMesh(validationIssues)
        }

        // Optionally fill in tangents via MikkTSpace when we have normals + UVs.
        let prepared: Mesh = {
            if generateTangentsIfMissing,
               mesh.tangents == nil,
               mesh.normals != nil,
               mesh.textureCoordinates != nil {
                return mesh.withTangents()
            }
            return mesh
        }()

        let parts = prepared.submeshes.enumerated().map { idx, submesh in
            buildPart(for: submesh, index: idx, in: prepared)
        }

        do {
            // Build a single Model containing one Part per submesh so the
            // submesh structure is preserved end-to-end.
            var contents = Self.Contents()
            contents.models = .init([
                Self.Model(id: "main", parts: parts)
            ])
            return try Self.generate(from: contents)
        } catch {
            throw MeshResourceConversionError.generationFailed(error)
        }
    }

    // MARK: - Part construction

    @MainActor
    private static func buildPart(for submesh: Mesh.Submesh, index: Int, in mesh: Mesh) -> MeshResource.Part {
        let name = submesh.label ?? "submesh_\(index)"
        var part = Self.Part(id: name, materialIndex: 0)

        let hasNormals = mesh.normals != nil
        let hasUVs = mesh.textureCoordinates != nil
        let hasTangents = mesh.tangents != nil
        let hasColors = mesh.colors != nil // collected for dedup parity only

        // Build deduplicated per-vertex arrays for this submesh. Two corners with
        // the same position but different attributes become two distinct vertices.
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var tangents: [SIMD3<Float>] = []
        var colors: [SIMD4<Float>] = []
        var triangleIndices: [UInt32] = []

        // Dedup key: position vertex ID + attribute hashes.
        var dedup: [VertexKey: UInt32] = [:]

        for faceID in submesh.faces {
            let vertexIDs = mesh.topology.vertexLoop(for: faceID)
            guard vertexIDs.count >= 3 else { continue }

            // VertexID → HalfEdgeID in this face (for per-corner attribute lookup).
            let heLoop = mesh.topology.halfEdgeLoop(for: faceID)
            var vertexToHE: [Int: HalfEdgeTopology.HalfEdgeID] = [:]
            for heID in heLoop {
                vertexToHE[mesh.topology.halfEdges[heID.raw].origin.raw] = heID
            }

            // Triangulate (passes triangles through unchanged).
            let triangles: [(HalfEdgeTopology.VertexID, HalfEdgeTopology.VertexID, HalfEdgeTopology.VertexID)]
            if vertexIDs.count == 3 {
                triangles = [(vertexIDs[0], vertexIDs[1], vertexIDs[2])]
            } else {
                triangles = mesh.triangulateFace(vertexIDs: vertexIDs)
            }

            for (v0, v1, v2) in triangles {
                for vid in [v0, v1, v2] {
                    let heID = vertexToHE[vid.raw]
                    let key = VertexKey(
                        vertex: vid.raw,
                        normal: hasNormals ? mesh.normals![heID!.raw] : nil,
                        uv: hasUVs ? mesh.textureCoordinates![heID!.raw] : nil,
                        tangent: hasTangents ? mesh.tangents![heID!.raw] : nil,
                        color: hasColors ? mesh.colors![heID!.raw] : nil
                    )

                    if let existing = dedup[key] {
                        triangleIndices.append(existing)
                    } else {
                        let newIndex = UInt32(positions.count)
                        positions.append(mesh.positions[vid.raw])
                        if hasNormals { normals.append(mesh.normals![heID!.raw]) }
                        if hasUVs { uvs.append(mesh.textureCoordinates![heID!.raw]) }
                        if hasTangents { tangents.append(mesh.tangents![heID!.raw]) }
                        if hasColors { colors.append(mesh.colors![heID!.raw]) }
                        dedup[key] = newIndex
                        triangleIndices.append(newIndex)
                    }
                }
            }
        }

        part[MeshBuffers.positions] = MeshBuffer(positions)
        if hasNormals { part[MeshBuffers.normals] = MeshBuffer(normals) }
        if hasUVs { part[MeshBuffers.textureCoordinates] = MeshBuffer(uvs) }
        if hasTangents { part[MeshBuffers.tangents] = MeshBuffer(tangents) }
        // Note: per-vertex colors aren't exposed by MeshResource.Part's standard
        // semantics; intentionally dropped. Bake them into a material/texture
        // downstream if needed.
        _ = colors
        part.triangleIndices = MeshBuffer(triangleIndices)
        return part
    }
}

// MARK: - Vertex dedup key

private struct VertexKey: Hashable {
    let vertex: Int
    let normalBits: SIMD3<UInt32>?
    let uvBits: SIMD2<UInt32>?
    let tangentBits: SIMD3<UInt32>?
    let colorBits: SIMD4<UInt32>?

    init(vertex: Int, normal: SIMD3<Float>?, uv: SIMD2<Float>?, tangent: SIMD3<Float>?, color: SIMD4<Float>?) {
        self.vertex = vertex
        self.normalBits = normal.map { SIMD3($0.x.bitPattern, $0.y.bitPattern, $0.z.bitPattern) }
        self.uvBits = uv.map { SIMD2($0.x.bitPattern, $0.y.bitPattern) }
        self.tangentBits = tangent.map { SIMD3($0.x.bitPattern, $0.y.bitPattern, $0.z.bitPattern) }
        self.colorBits = color.map { SIMD4($0.x.bitPattern, $0.y.bitPattern, $0.z.bitPattern, $0.w.bitPattern) }
    }
}
