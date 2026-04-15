import simd

/// A mesh combining half-edge topology with SoA vertex/corner attributes.
///
/// Positions are per-vertex (indexed by `VertexID.raw`).
/// Normals, UVs, and colors can be per-vertex or per-corner (indexed by `HalfEdgeID.raw`).
/// Material assignment is per-face (indexed by `FaceID.raw`).
public struct Mesh: Sendable, Equatable {
    /// The combinatorial topology (vertices, half-edges, faces, wiring).
    public var topology: HalfEdgeTopology

    // MARK: - Per-vertex attributes (indexed by VertexID.raw)

    /// Vertex positions. Count must equal `topology.vertices.count`.
    public var positions: [SIMD3<Float>]

    // MARK: - Per-corner attributes (indexed by HalfEdgeID.raw)

    /// Per-corner normals. When nil, normals are not assigned.
    public var normals: [SIMD3<Float>]?

    /// Per-corner texture coordinates. When nil, UVs are not assigned.
    public var textureCoordinates: [SIMD2<Float>]?

    /// Per-corner tangents. When nil, tangents are not assigned.
    public var tangents: [SIMD3<Float>]?

    /// Per-corner bitangents. When nil, bitangents are not assigned.
    public var bitangents: [SIMD3<Float>]?

    /// Per-corner colors. When nil, colors are not assigned.
    public var colors: [SIMD4<Float>]?

    // MARK: - Submeshes

    /// Face groups. Each submesh references a subset of faces.
    /// Default: one submesh containing all faces.
    public var submeshes: [Submesh]

    // MARK: - Init

    /// A named group of faces within the mesh.
    public struct Submesh: Sendable, Equatable {
        public var label: String?
        public var faces: [HalfEdgeTopology.FaceID]

        public init(label: String? = nil, faces: [HalfEdgeTopology.FaceID]) {
            self.label = label
            self.faces = faces
        }
    }

    public init(
        topology: HalfEdgeTopology,
        positions: [SIMD3<Float>],
        normals: [SIMD3<Float>]? = nil,
        textureCoordinates: [SIMD2<Float>]? = nil,
        tangents: [SIMD3<Float>]? = nil,
        bitangents: [SIMD3<Float>]? = nil,
        colors: [SIMD4<Float>]? = nil,
        submeshes: [Submesh]? = nil
    ) {
        self.topology = topology
        self.positions = positions
        self.normals = normals
        self.textureCoordinates = textureCoordinates
        self.tangents = tangents
        self.bitangents = bitangents
        self.colors = colors
        self.submeshes = submeshes ?? [Submesh(faces: topology.faces.map(\.id))]
    }

    /// Build from indexed vertex positions and face definitions.
    public init(positions: [SIMD3<Float>], faces: [[Int]]) {
        let faceDefs = faces.map { HalfEdgeTopology.FaceDefinition(outer: $0) }
        let topo = HalfEdgeTopology(vertexCount: positions.count, faces: faceDefs)
        self.init(topology: topo, positions: positions)
    }

    /// Build from indexed vertex positions and face definitions with holes.
    public init(positions: [SIMD3<Float>], faces: [HalfEdgeTopology.FaceDefinition]) {
        let topo = HalfEdgeTopology(vertexCount: positions.count, faces: faces)
        self.init(topology: topo, positions: positions)
    }
}

// MARK: - Convenience accessors

public extension Mesh {
    /// Number of vertices.
    var vertexCount: Int { topology.vertices.count }

    /// Number of faces.
    var faceCount: Int { topology.faces.count }

    /// Number of unique undirected edges.
    var edgeCount: Int { topology.undirectedEdges().count }

    /// Whether this mesh is a closed 2-manifold (no boundary edges, no
    /// non-manifold vertices).
    var isManifold: Bool { topology.isManifold }

    /// Position of a vertex.
    func position(of vertex: HalfEdgeTopology.VertexID) -> SIMD3<Float> {
        positions[vertex.raw]
    }

    /// Positions of a face's boundary vertices.
    func facePositions(_ face: HalfEdgeTopology.FaceID) -> [SIMD3<Float>] {
        topology.vertexLoop(for: face).map { positions[$0.raw] }
    }

    /// Compute the center (centroid) of the mesh.
    var center: SIMD3<Float> {
        guard !positions.isEmpty else {
            return .zero
        }
        return positions.reduce(.zero, +) / Float(positions.count)
    }

    /// Compute the face normal from vertex positions (Newell's method).
    func faceNormal(_ face: HalfEdgeTopology.FaceID) -> SIMD3<Float> {
        let pts = facePositions(face)
        guard pts.count >= 3 else {
            return SIMD3<Float>(0, 0, 1)
        }
        // Newell's method — works for non-planar polygons too
        var normal = SIMD3<Float>.zero
        for idx in 0..<pts.count {
            let current = pts[idx]
            let next = pts[(idx + 1) % pts.count]
            normal.x += (current.y - next.y) * (current.z + next.z)
            normal.y += (current.z - next.z) * (current.x + next.x)
            normal.z += (current.x - next.x) * (current.y + next.y)
        }
        let len = simd_length(normal)
        return len > 0 ? normal / len : SIMD3<Float>(0, 0, 1)
    }

    /// Compute the centroid of a face.
    func faceCentroid(_ face: HalfEdgeTopology.FaceID) -> SIMD3<Float> {
        let pts = facePositions(face)
        guard !pts.isEmpty else {
            return .zero
        }
        return pts.reduce(.zero, +) / Float(pts.count)
    }

    /// Validates topology and attribute array sizes.
    func validate() -> String? {
        if let error = topology.validate() {
            return error
        }
        if positions.count != topology.vertices.count {
            return "positions.count (\(positions.count)) != vertex count (\(topology.vertices.count))"
        }
        if let normals, normals.count != topology.halfEdges.count {
            return "normals.count (\(normals.count)) != halfEdge count (\(topology.halfEdges.count))"
        }
        if let textureCoordinates, textureCoordinates.count != topology.halfEdges.count {
            return "textureCoordinates.count (\(textureCoordinates.count)) != halfEdge count (\(topology.halfEdges.count))"
        }
        if let tangents, tangents.count != topology.halfEdges.count {
            return "tangents.count (\(tangents.count)) != halfEdge count (\(topology.halfEdges.count))"
        }
        if let bitangents, bitangents.count != topology.halfEdges.count {
            return "bitangents.count (\(bitangents.count)) != halfEdge count (\(topology.halfEdges.count))"
        }
        if let colors, colors.count != topology.halfEdges.count {
            return "colors.count (\(colors.count)) != halfEdge count (\(topology.halfEdges.count))"
        }
        return nil
    }

    /// The axis-aligned bounding box of the mesh as (min, max).
    var bounds: (min: SIMD3<Float>, max: SIMD3<Float>) {
        guard let first = positions.first else {
            return (.zero, .zero)
        }
        var lo = first
        var hi = first
        for p in positions.dropFirst() {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        return (lo, hi)
    }

    /// Uniformly scale and translate positions so the bounding box fits within
    /// the given extents, centered at the origin.
    ///
    /// Axes with zero extent in the target are ignored (positions on that axis
    /// are left unchanged). This allows 2D shapes to pass `SIMD3(w, h, 0)`.
    mutating func fitToExtents(_ extents: SIMD3<Float>) {
        let (lo, hi) = bounds
        let currentSize = hi - lo
        let currentCenter = (lo + hi) / 2

        // Compute per-axis scale, ignoring axes with zero current or target extent
        var scale: SIMD3<Float> = [1, 1, 1]
        for i in 0..<3 {
            if currentSize[i] > 0 && extents[i] > 0 {
                scale[i] = extents[i] / currentSize[i]
            }
        }

        for i in positions.indices {
            positions[i] = (positions[i] - currentCenter) * scale
        }
    }

    /// Uniformly scale and translate positions so the mesh fits within a sphere
    /// of the given `diameter`, centered at the origin.
    ///
    /// Aspect ratio is preserved — the longest axis of the bounding box
    /// matches the diameter.
    mutating func fitToDiameter(_ diameter: Float) {
        let (lo, hi) = bounds
        let currentSize = hi - lo
        let currentCenter = (lo + hi) / 2
        let maxExtent = max(currentSize.x, max(currentSize.y, currentSize.z))
        guard maxExtent > 0 else { return }
        let scale = diameter / maxExtent

        for i in positions.indices {
            positions[i] = (positions[i] - currentCenter) * scale
        }
    }
}

// MARK: - Transforms

public extension Mesh {
    /// Translate all positions by the given offset.
    mutating func translate(by offset: SIMD3<Float>) {
        for i in positions.indices {
            positions[i] += offset
        }
    }

    /// Return a new mesh with all positions translated by the given offset.
    func translated(by offset: SIMD3<Float>) -> Mesh {
        var copy = self
        copy.translate(by: offset)
        return copy
    }

    /// Scale all positions by per-axis factors.
    mutating func scale(by factor: SIMD3<Float>) {
        for i in positions.indices {
            positions[i] *= factor
        }
        transformDirectionAttributes { direction in
            // For non-uniform scale, normals transform by the inverse-transpose.
            // For directions like tangents/bitangents, apply the scale directly.
            direction
        } normalTransform: { normal in
            let inverseScale = SIMD3<Float>(1 / factor.x, 1 / factor.y, 1 / factor.z)
            let transformed = normal * inverseScale
            let len = simd_length(transformed)
            return len > 0 ? transformed / len : normal
        }
    }

    /// Scale all positions uniformly.
    mutating func scale(by factor: Float) {
        scale(by: SIMD3<Float>(repeating: factor))
    }

    /// Return a new mesh with positions scaled by per-axis factors.
    func scaled(by factor: SIMD3<Float>) -> Mesh {
        var copy = self
        copy.scale(by: factor)
        return copy
    }

    /// Return a new mesh with positions scaled uniformly.
    func scaled(by factor: Float) -> Mesh {
        var copy = self
        copy.scale(by: factor)
        return copy
    }

    /// Rotate all positions and direction attributes by a quaternion.
    mutating func rotate(by quaternion: simd_quatf) {
        let matrix = simd_matrix3x3(quaternion)
        for i in positions.indices {
            positions[i] = matrix * positions[i]
        }
        transformDirectionAttributes { direction in
            let transformed = matrix * direction
            let len = simd_length(transformed)
            return len > 0 ? transformed / len : direction
        } normalTransform: { normal in
            let transformed = matrix * normal
            let len = simd_length(transformed)
            return len > 0 ? transformed / len : normal
        }
    }

    /// Return a new mesh rotated by a quaternion.
    func rotated(by quaternion: simd_quatf) -> Mesh {
        var copy = self
        copy.rotate(by: quaternion)
        return copy
    }

    /// Apply a 4×4 transform to positions and direction attributes.
    mutating func transform(by matrix: simd_float4x4) {
        let upperLeft = simd_float3x3(
            SIMD3<Float>(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
            SIMD3<Float>(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
            SIMD3<Float>(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        )
        let normalMatrix: simd_float3x3 = {
            let det = upperLeft.determinant
            guard abs(det) > 1e-8 else {
                return upperLeft
            }
            return upperLeft.inverse.transpose
        }()

        for i in positions.indices {
            let p = positions[i]
            let transformed = matrix * SIMD4<Float>(p.x, p.y, p.z, 1)
            positions[i] = SIMD3<Float>(transformed.x, transformed.y, transformed.z)
        }
        transformDirectionAttributes { direction in
            let transformed = upperLeft * direction
            let len = simd_length(transformed)
            return len > 0 ? transformed / len : direction
        } normalTransform: { normal in
            let transformed = normalMatrix * normal
            let len = simd_length(transformed)
            return len > 0 ? transformed / len : normal
        }
    }

    /// Return a new mesh transformed by a 4×4 matrix.
    func transformed(by matrix: simd_float4x4) -> Mesh {
        var copy = self
        copy.transform(by: matrix)
        return copy
    }
}

// MARK: - Internal helpers

private extension Mesh {
    /// Apply transforms to direction-based attributes (normals, tangents, bitangents).
    mutating func transformDirectionAttributes(
        directionTransform: (SIMD3<Float>) -> SIMD3<Float>,
        normalTransform: (SIMD3<Float>) -> SIMD3<Float>
    ) {
        if var n = normals {
            for i in n.indices {
                n[i] = normalTransform(n[i])
            }
            normals = n
        }
        if var t = tangents {
            for i in t.indices {
                t[i] = directionTransform(t[i])
            }
            tangents = t
        }
        if var b = bitangents {
            for i in b.indices {
                b[i] = directionTransform(b[i])
            }
            bitangents = b
        }
    }
}
