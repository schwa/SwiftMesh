import Foundation
import simd

public struct PolygonMesh: Equatable, Sendable {

    internal var topology: HalfEdgeTopology
    internal var positions: [SIMD3<Float>]

    public struct Edge: Hashable, Sendable {
        public var start: SIMD3<Float>
        public var end: SIMD3<Float>
    }

    public struct Face: Hashable, Sendable {
        public var vertices: [SIMD3<Float>]
    }

    public init(vertices: [SIMD3<Float>], faces: [[Int]]) {
        self.positions = vertices
        let faceDefs = faces.map { HalfEdgeTopology.FaceDefinition(outer: $0) }
        self.topology = HalfEdgeTopology(vertexCount: vertices.count, faces: faceDefs)
    }

    public init(vertices: [SIMD3<Float>], faces: [Face]) {
        // Deduplicate vertex positions to build an indexed representation
        var indexedVertices: [SIMD3<Float>] = []
        var positionToIndex: [SIMD3<Float>: Int] = [:]

        func index(for position: SIMD3<Float>) -> Int {
            if let existing = positionToIndex[position] {
                return existing
            }
            let idx = indexedVertices.count
            indexedVertices.append(position)
            positionToIndex[position] = idx
            return idx
        }

        let faceDefs = faces.map { face in
            HalfEdgeTopology.FaceDefinition(outer: face.vertices.map { index(for: $0) })
        }
        self.positions = indexedVertices
        self.topology = HalfEdgeTopology(vertexCount: indexedVertices.count, faces: faceDefs)
    }
}

// MARK: - Vertices & Faces

public extension PolygonMesh {
    var vertices: [SIMD3<Float>] {
        positions
    }

    var faces: [Face] {
        topology.faces.map { face in
            let vertexIDs = topology.vertexLoop(for: face.id)
            return Face(vertices: vertexIDs.map { positions[$0.raw] })
        }
    }
}

// MARK: - Edges & Centers

public extension PolygonMesh {
    var edges: [Edge] {
        topology.undirectedEdges().map { vertexA, vertexB in
            Edge(start: positions[vertexA.raw], end: positions[vertexB.raw])
        }
    }

    var center: SIMD3<Float> {
        let verts = vertices
        guard !verts.isEmpty else {
            return SIMD3<Float>(repeating: 0)
        }
        return verts.reduce(SIMD3<Float>(repeating: 0), +) / Float(verts.count)
    }
}

// MARK: - Topology queries

public extension PolygonMesh {
    /// Validates the internal mesh structure. Returns nil if valid.
    func validate() -> String? {
        topology.validate()
    }

    /// Number of faces in the mesh.
    var faceCount: Int {
        topology.faces.count
    }

    /// Number of unique undirected edges.
    var edgeCount: Int {
        topology.undirectedEdges().count
    }
}

// MARK: - Edge

public extension PolygonMesh.Edge {
    var center: SIMD3<Float> {
        (start + end) / 2
    }
}

// MARK: - Face

public extension PolygonMesh.Face {
    var edges: [PolygonMesh.Edge] {
        guard let first = vertices.first, vertices.count > 1 else {
            return []
        }
        var result: [PolygonMesh.Edge] = []
        let wrapped = vertices + [first]
        for index in 0..<(wrapped.count - 1) {
            result.append(PolygonMesh.Edge(start: wrapped[index], end: wrapped[index + 1]))
        }
        return result
    }

    var normal: SIMD3<Float> {
        guard vertices.count >= 3 else {
            return SIMD3<Float>(0, 0, 1)
        }
        let a = vertices[0]
        let b = vertices[1]
        let c = vertices[2]
        return simd_normalize(simd_cross(b - a, c - a))
    }

    var center: SIMD3<Float> {
        vertices.reduce(SIMD3<Float>(repeating: 0), +) / Float(vertices.count)
    }
}

// MARK: - Platonic Solids

public extension PolygonMesh {
    static let cube = PolygonMesh(
        vertices: [
            SIMD3<Float>(-1, -1, -1),
            SIMD3<Float>(1, -1, -1),
            SIMD3<Float>(1, 1, -1),
            SIMD3<Float>(-1, 1, -1),
            SIMD3<Float>(-1, -1, 1),
            SIMD3<Float>(1, -1, 1),
            SIMD3<Float>(1, 1, 1),
            SIMD3<Float>(-1, 1, 1)
        ].map { simd_normalize($0) },
        faces: [
            [0, 3, 2, 1], // front (facing -Z)
            [4, 5, 6, 7], // back (facing +Z)
            [0, 1, 5, 4], // bottom (facing -Y)
            [3, 7, 6, 2], // top (facing +Y)
            [1, 2, 6, 5], // right (facing +X)
            [0, 4, 7, 3]  // left (facing -X)
        ]
    )

    static let dodecahedron: PolygonMesh = {
        let phi: Float = (1.0 + sqrt(5.0)) / 2.0
        let invPhi: Float = 1.0 / phi

        let vertices: [SIMD3<Float>] = [
            SIMD3<Float>(1, 1, 1),
            SIMD3<Float>(1, 1, -1),
            SIMD3<Float>(1, -1, 1),
            SIMD3<Float>(1, -1, -1),
            SIMD3<Float>(-1, 1, 1),
            SIMD3<Float>(-1, 1, -1),
            SIMD3<Float>(-1, -1, 1),
            SIMD3<Float>(-1, -1, -1),
            SIMD3<Float>(0, invPhi, phi),
            SIMD3<Float>(0, invPhi, -phi),
            SIMD3<Float>(0, -invPhi, phi),
            SIMD3<Float>(0, -invPhi, -phi),
            SIMD3<Float>(invPhi, phi, 0),
            SIMD3<Float>(invPhi, -phi, 0),
            SIMD3<Float>(-invPhi, phi, 0),
            SIMD3<Float>(-invPhi, -phi, 0),
            SIMD3<Float>(phi, 0, invPhi),
            SIMD3<Float>(phi, 0, -invPhi),
            SIMD3<Float>(-phi, 0, invPhi),
            SIMD3<Float>(-phi, 0, -invPhi)
        ].map { simd_normalize($0) }

        let faces: [[Int]] = [
            [0, 8, 10, 2, 16],
            [0, 16, 17, 1, 12],
            [0, 12, 14, 4, 8],
            [1, 17, 3, 11, 9],
            [1, 9, 5, 14, 12],
            [2, 10, 6, 15, 13],
            [2, 13, 3, 17, 16],
            [3, 13, 15, 7, 11],
            [4, 14, 5, 19, 18],
            [4, 18, 6, 10, 8],
            [5, 9, 11, 7, 19],
            [6, 18, 19, 7, 15]
        ]

        return PolygonMesh(vertices: vertices, faces: faces)
    }()

    static let tetrahedron = PolygonMesh(vertices: [SIMD3<Float>(1, 1, 1), SIMD3<Float>(-1, -1, 1), SIMD3<Float>(-1, 1, -1), SIMD3<Float>(1, -1, -1)].map { simd_normalize($0) }, faces: [[0, 1, 2], [0, 3, 1], [0, 2, 3], [1, 3, 2]])

    static let octahedron = PolygonMesh(vertices: [SIMD3<Float>(1, 0, 0), SIMD3<Float>(-1, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, -1, 0), SIMD3<Float>(0, 0, 1), SIMD3<Float>(0, 0, -1)], faces: [[0, 2, 4], [0, 4, 3], [0, 3, 5], [0, 5, 2], [1, 2, 5], [1, 5, 3], [1, 3, 4], [1, 4, 2]])

    static let icosahedron: PolygonMesh = {
        let phi: Float = (1.0 + sqrt(5.0)) / 2.0
        let vertices: [SIMD3<Float>] = [SIMD3<Float>(-1, phi, 0), SIMD3<Float>(1, phi, 0), SIMD3<Float>(-1, -phi, 0), SIMD3<Float>(1, -phi, 0), SIMD3<Float>(0, -1, phi), SIMD3<Float>(0, 1, phi), SIMD3<Float>(0, -1, -phi), SIMD3<Float>(0, 1, -phi), SIMD3<Float>(phi, 0, -1), SIMD3<Float>(phi, 0, 1), SIMD3<Float>(-phi, 0, -1), SIMD3<Float>(-phi, 0, 1)].map { simd_normalize($0) }
        let faces: [[Int]] = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
        return PolygonMesh(vertices: vertices, faces: faces)
    }()
}
