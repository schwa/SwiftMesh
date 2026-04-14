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

    /// Per-corner colors. When nil, colors are not assigned.
    public var colors: [SIMD4<Float>]?

    // MARK: - Per-face attributes (indexed by FaceID.raw)

    /// Per-face material slot index. When nil, all faces use material 0.
    public var faceMaterials: [Int]?

    // MARK: - Init

    public init(
        topology: HalfEdgeTopology,
        positions: [SIMD3<Float>],
        normals: [SIMD3<Float>]? = nil,
        textureCoordinates: [SIMD2<Float>]? = nil,
        colors: [SIMD4<Float>]? = nil,
        faceMaterials: [Int]? = nil
    ) {
        self.topology = topology
        self.positions = positions
        self.normals = normals
        self.textureCoordinates = textureCoordinates
        self.colors = colors
        self.faceMaterials = faceMaterials
    }

    /// Build from indexed vertex positions and face definitions.
    public init(positions: [SIMD3<Float>], faces: [[Int]]) {
        let faceDefs = faces.map { HalfEdgeTopology.FaceDefinition(outer: $0) }
        self.topology = HalfEdgeTopology(vertexCount: positions.count, faces: faceDefs)
        self.positions = positions
    }

    /// Build from indexed vertex positions and face definitions with holes.
    public init(positions: [SIMD3<Float>], faces: [HalfEdgeTopology.FaceDefinition]) {
        self.topology = HalfEdgeTopology(vertexCount: positions.count, faces: faces)
        self.positions = positions
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

    /// Material slot for a face. Returns 0 if no material tags are assigned.
    func faceMaterial(_ face: HalfEdgeTopology.FaceID) -> Int {
        faceMaterials?[face.raw] ?? 0
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
        if let colors, colors.count != topology.halfEdges.count {
            return "colors.count (\(colors.count)) != halfEdge count (\(topology.halfEdges.count))"
        }
        if let faceMaterials, faceMaterials.count != topology.faces.count {
            return "faceMaterials.count (\(faceMaterials.count)) != face count (\(topology.faces.count))"
        }
        return nil
    }
}

// MARK: - Platonic Solids

public extension Mesh {
    static let tetrahedron: Mesh = {
        let positions: [SIMD3<Float>] = [
            SIMD3(1, 1, 1), SIMD3(-1, -1, 1), SIMD3(-1, 1, -1), SIMD3(1, -1, -1)
        ].map { simd_normalize($0) }
        return Mesh(positions: positions, faces: [
            [0, 1, 2], [0, 3, 1], [0, 2, 3], [1, 3, 2]
        ])
    }()

    static let cube: Mesh = {
        let positions: [SIMD3<Float>] = [
            SIMD3(-1, -1, -1), SIMD3(1, -1, -1), SIMD3(1, 1, -1), SIMD3(-1, 1, -1),
            SIMD3(-1, -1, 1), SIMD3(1, -1, 1), SIMD3(1, 1, 1), SIMD3(-1, 1, 1)
        ].map { simd_normalize($0) }
        return Mesh(positions: positions, faces: [
            [0, 3, 2, 1], [4, 5, 6, 7],
            [0, 1, 5, 4], [3, 7, 6, 2],
            [1, 2, 6, 5], [0, 4, 7, 3]
        ])
    }()

    static let octahedron: Mesh = {
        let positions: [SIMD3<Float>] = [
            SIMD3(1, 0, 0), SIMD3(-1, 0, 0), SIMD3(0, 1, 0),
            SIMD3(0, -1, 0), SIMD3(0, 0, 1), SIMD3(0, 0, -1)
        ]
        return Mesh(positions: positions, faces: [
            [0, 2, 4], [0, 4, 3], [0, 3, 5], [0, 5, 2],
            [1, 2, 5], [1, 5, 3], [1, 3, 4], [1, 4, 2]
        ])
    }()

    static let icosahedron: Mesh = {
        let phi: Float = (1.0 + sqrt(5.0)) / 2.0
        let positions: [SIMD3<Float>] = [
            SIMD3(-1, phi, 0), SIMD3(1, phi, 0), SIMD3(-1, -phi, 0), SIMD3(1, -phi, 0),
            SIMD3(0, -1, phi), SIMD3(0, 1, phi), SIMD3(0, -1, -phi), SIMD3(0, 1, -phi),
            SIMD3(phi, 0, -1), SIMD3(phi, 0, 1), SIMD3(-phi, 0, -1), SIMD3(-phi, 0, 1)
        ].map { simd_normalize($0) }
        return Mesh(positions: positions, faces: [
            [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
            [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
            [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
            [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]
        ])
    }()

    static let dodecahedron: Mesh = {
        let phi: Float = (1.0 + sqrt(5.0)) / 2.0
        let invPhi: Float = 1.0 / phi
        let positions: [SIMD3<Float>] = [
            SIMD3(1, 1, 1), SIMD3(1, 1, -1), SIMD3(1, -1, 1), SIMD3(1, -1, -1),
            SIMD3(-1, 1, 1), SIMD3(-1, 1, -1), SIMD3(-1, -1, 1), SIMD3(-1, -1, -1),
            SIMD3(0, invPhi, phi), SIMD3(0, invPhi, -phi),
            SIMD3(0, -invPhi, phi), SIMD3(0, -invPhi, -phi),
            SIMD3(invPhi, phi, 0), SIMD3(invPhi, -phi, 0),
            SIMD3(-invPhi, phi, 0), SIMD3(-invPhi, -phi, 0),
            SIMD3(phi, 0, invPhi), SIMD3(phi, 0, -invPhi),
            SIMD3(-phi, 0, invPhi), SIMD3(-phi, 0, -invPhi)
        ].map { simd_normalize($0) }
        return Mesh(positions: positions, faces: [
            [0, 8, 10, 2, 16], [0, 16, 17, 1, 12], [0, 12, 14, 4, 8],
            [1, 17, 3, 11, 9], [1, 9, 5, 14, 12], [2, 10, 6, 15, 13],
            [2, 13, 3, 17, 16], [3, 13, 15, 7, 11], [4, 14, 5, 19, 18],
            [4, 18, 6, 10, 8], [5, 9, 11, 7, 19], [6, 18, 19, 7, 15]
        ])
    }()
}
