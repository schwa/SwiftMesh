import simd

/// The optional per-corner attribute arrays of a ``Mesh``, handled as one unit.
///
/// Arrays are indexed by corner (half-edge) index. Every operation applies to each present
/// attribute, so adding a new attribute only touches this type and the forwarding accessors on
/// ``Mesh``. Direction attributes (normals, tangents, bitangents) are renormalized after blending.
@usableFromInline
struct CornerAttributes: Sendable, Equatable {
    @usableFromInline var normals: [SIMD3<Float>]?
    @usableFromInline var textureCoordinates: [SIMD2<Float>]?
    @usableFromInline var tangents: [SIMD3<Float>]?
    @usableFromInline var bitangents: [SIMD3<Float>]?
    @usableFromInline var colors: [SIMD4<Float>]?

    init(normals: [SIMD3<Float>]? = nil, textureCoordinates: [SIMD2<Float>]? = nil, tangents: [SIMD3<Float>]? = nil, bitangents: [SIMD3<Float>]? = nil, colors: [SIMD4<Float>]? = nil) {
        self.normals = normals
        self.textureCoordinates = textureCoordinates
        self.tangents = tangents
        self.bitangents = bitangents
        self.colors = colors
    }

    init(of mesh: Mesh) {
        self = mesh.cornerAttributes
    }

    func apply(to mesh: inout Mesh) {
        mesh.cornerAttributes = self
    }

    /// Number of corners, or 0 when no attribute is present.
    var cornerCount: Int {
        normals?.count ?? textureCoordinates?.count ?? tangents?.count ?? bitangents?.count ?? colors?.count ?? 0
    }

    /// One corner of a blend: an existing corner index and its weight.
    typealias Weight = (corner: Int, weight: Float)

    /// New attributes where corner `i` takes the value of old corner `corners[i]`.
    func gathered(_ corners: [Int]) -> Self {
        var result = self
        result.modifyEach(Gather(corners: corners))
        return result
    }

    /// New attributes where corner `i` is the weighted sum of the old corners in `blends[i]`.
    func blended(_ blends: [[Weight]]) -> Self {
        var result = self
        result.modifyEach(Blend(blends: blends))
        return result
    }

    /// Appends one corner that copies `corner`.
    mutating func append(copying corner: Int) {
        modifyEach(AppendBlend(weights: [(corner, 1)]))
    }

    /// Appends one corner that blends existing corners.
    mutating func append(blending weights: [Weight]) {
        modifyEach(AppendBlend(weights: weights))
    }

    /// Overwrites corner `target` with the value of corner `source`.
    mutating func copyCorner(from source: Int, to target: Int) {
        modifyEach(Copy(source: source, target: target))
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
}

// MARK: - Per-attribute dispatch

/// An edit applied to each present attribute array in turn.
private protocol CornerAttributeModifier {
    func modify<T: SIMD>(_ values: inout [T], isDirection: Bool) where T.Scalar == Float
}

private extension CornerAttributes {
    /// The one place that lists every attribute and its rules.
    mutating func modifyEach(_ modifier: some CornerAttributeModifier) {
        func visit<T: SIMD>(_ values: inout [T]?, isDirection: Bool) where T.Scalar == Float {
            if values != nil {
                modifier.modify(&values!, isDirection: isDirection)
            }
        }
        visit(&normals, isDirection: true)
        visit(&textureCoordinates, isDirection: false)
        visit(&tangents, isDirection: true)
        visit(&bitangents, isDirection: true)
        visit(&colors, isDirection: false)
    }
}

private func weightedSum<T: SIMD>(_ values: [T], _ weights: [CornerAttributes.Weight], isDirection: Bool) -> T where T.Scalar == Float {
    var result = T()
    for (corner, weight) in weights {
        result += values[corner] * weight
    }
    guard isDirection else {
        return result
    }
    let length = (result * result).sum().squareRoot()
    return length > 0 ? result / length : result
}

private struct Gather: CornerAttributeModifier {
    let corners: [Int]
    func modify<T: SIMD>(_ values: inout [T], isDirection _: Bool) where T.Scalar == Float {
        values = corners.map { values[$0] }
    }
}

private struct Blend: CornerAttributeModifier {
    let blends: [[CornerAttributes.Weight]]
    func modify<T: SIMD>(_ values: inout [T], isDirection: Bool) where T.Scalar == Float {
        let source = values
        values = blends.map { weightedSum(source, $0, isDirection: isDirection) }
    }
}

private struct AppendBlend: CornerAttributeModifier {
    let weights: [CornerAttributes.Weight]
    func modify<T: SIMD>(_ values: inout [T], isDirection: Bool) where T.Scalar == Float {
        // A single copy needs no renormalizing, so stored values round-trip exactly.
        if weights.count == 1, weights[0].weight == 1 {
            values.append(values[weights[0].corner])
        } else {
            values.append(weightedSum(values, weights, isDirection: isDirection))
        }
    }
}

private struct Copy: CornerAttributeModifier {
    let source: Int
    let target: Int
    func modify<T: SIMD>(_ values: inout [T], isDirection _: Bool) where T.Scalar == Float {
        values[target] = values[source]
    }
}

// MARK: - Rebuild order

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
