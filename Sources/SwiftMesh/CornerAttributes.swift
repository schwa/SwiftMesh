import simd

/// The optional per-corner attribute arrays of a ``Mesh``, handled as one unit.
///
/// Arrays are indexed by corner (half-edge) index. Operations apply to every
/// present attribute, so adding a new attribute only touches this type.
struct CornerAttributes: Sendable, Equatable {
    var normals: [SIMD3<Float>]?
    var textureCoordinates: [SIMD2<Float>]?
    var tangents: [SIMD3<Float>]?
    var bitangents: [SIMD3<Float>]?
    var colors: [SIMD4<Float>]?

    init(normals: [SIMD3<Float>]? = nil, textureCoordinates: [SIMD2<Float>]? = nil, tangents: [SIMD3<Float>]? = nil, bitangents: [SIMD3<Float>]? = nil, colors: [SIMD4<Float>]? = nil) {
        self.normals = normals
        self.textureCoordinates = textureCoordinates
        self.tangents = tangents
        self.bitangents = bitangents
        self.colors = colors
    }

    init(of mesh: Mesh) {
        self.init(normals: mesh.normals, textureCoordinates: mesh.textureCoordinates, tangents: mesh.tangents, bitangents: mesh.bitangents, colors: mesh.colors)
    }

    /// New attributes where corner `i` takes the value of old corner `corners[i]`.
    func gathered(_ corners: [Int]) -> Self {
        func gather<T>(_ values: [T]?) -> [T]? {
            values.map { values in corners.map { values[$0] } }
        }
        return Self(normals: gather(normals), textureCoordinates: gather(textureCoordinates), tangents: gather(tangents), bitangents: gather(bitangents), colors: gather(colors))
    }

    /// Concatenate in order. An attribute is kept only if every part has it.
    static func concatenated(_ parts: [Self]) -> Self {
        func concat<T>(_ path: KeyPath<Self, [T]?>) -> [T]? {
            var result: [T] = []
            for part in parts {
                guard let values = part[keyPath: path] else {
                    return nil
                }
                result += values
            }
            return result
        }
        return Self(normals: concat(\.normals), textureCoordinates: concat(\.textureCoordinates), tangents: concat(\.tangents), bitangents: concat(\.bitangents), colors: concat(\.colors))
    }

    func apply(to mesh: inout Mesh) {
        mesh.normals = normals
        mesh.textureCoordinates = textureCoordinates
        mesh.tangents = tangents
        mesh.bitangents = bitangents
        mesh.colors = colors
    }
}

extension HalfEdgeTopology {
    /// Half-edges of `face` in the order `HalfEdgeTopology(vertexCount:faces:)` creates them when
    /// rebuilding from this face's vertex loops: outer loop then holes, skipping loops with fewer than
    /// 3 corners (and the whole face if its outer loop is skipped).
    func rebuildCornerOrder(for face: FaceID) -> [HalfEdgeID] {
        guard let start = faces[face.raw].edge else {
            return []
        }
        let outer = collectHalfEdgeLoop(startEdge: start)
        guard outer.count >= 3 else {
            return []
        }
        return faces[face.raw].holeEdges.reduce(into: outer) { result, holeEdge in
            let hole = collectHalfEdgeLoop(startEdge: holeEdge)
            if hole.count >= 3 {
                result += hole
            }
        }
    }
}
