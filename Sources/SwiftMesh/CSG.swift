import simd

/// The type of CSG (Constructive Solid Geometry) boolean operation.
public enum CSGOperation: Sendable {
    /// Combine two volumes into one (A ∪ B).
    case union
    /// Keep only the overlapping volume (A ∩ B).
    case intersection
    /// Subtract the second volume from the first (A − B).
    case difference

    var booleanOperation: BooleanOperation {
        switch self {
        case .union: .union
        case .intersection: .intersection
        case .difference: .difference
        }
    }
}

// MARK: - Mesh CSG API

public extension Mesh {
    /// Returns the CSG union of this mesh with another (A ∪ B).
    ///
    /// See ``csg(_:_:options:)`` for how the result is computed.
    ///
    /// - Parameters:
    ///   - other: The mesh to union with.
    ///   - mergeCoplanar: Merge adjacent coplanar triangles of the result back into n-gons
    ///     (only when the result has no attributes; see ``CSGOptions/mergeCoplanar``).
    /// - Returns: A new mesh representing the combined volume.
    func union(_ other: Mesh, mergeCoplanar: Bool = true) -> Mesh {
        csg(.union, other, options: CSGOptions(mergeCoplanar: mergeCoplanar))
    }

    /// Returns the CSG intersection of this mesh with another (A ∩ B).
    ///
    /// See ``csg(_:_:options:)`` for how the result is computed.
    ///
    /// - Parameters:
    ///   - other: The mesh to intersect with.
    ///   - mergeCoplanar: Merge adjacent coplanar triangles of the result back into n-gons
    ///     (only when the result has no attributes; see ``CSGOptions/mergeCoplanar``).
    /// - Returns: A new mesh containing only the shared volume.
    func intersection(_ other: Mesh, mergeCoplanar: Bool = true) -> Mesh {
        csg(.intersection, other, options: CSGOptions(mergeCoplanar: mergeCoplanar))
    }

    /// Returns the CSG difference of this mesh minus another (A − B).
    ///
    /// See ``csg(_:_:options:)`` for how the result is computed.
    ///
    /// - Parameters:
    ///   - other: The mesh volume to subtract.
    ///   - mergeCoplanar: Merge adjacent coplanar triangles of the result back into n-gons
    ///     (only when the result has no attributes; see ``CSGOptions/mergeCoplanar``).
    /// - Returns: A new mesh with the other's volume carved out.
    func difference(_ other: Mesh, mergeCoplanar: Bool = true) -> Mesh {
        csg(.difference, other, options: CSGOptions(mergeCoplanar: mergeCoplanar))
    }

    /// Performs a CSG operation with the robust Boolean (a Swift port of Manifold's).
    ///
    /// Both inputs must be closed manifolds; vertices at the same position (for example
    /// split at UV seams) are merged first. For manifold inputs the result is always a
    /// closed manifold: exact coincidences (touching or coplanar faces) are resolved by
    /// symbolic perturbation, so touching solids union into one and a mesh minus itself is
    /// empty. Degenerate slivers are removed, per-corner attributes are interpolated from
    /// the inputs (an attribute is kept only if both inputs have it), and submeshes are
    /// merged into one.
    ///
    /// An empty operand (no faces) counts as the empty solid: union returns the other mesh,
    /// intersection is empty, and difference returns `self`.
    ///
    /// - Returns: The result, or an empty mesh if either input is not a closed manifold.
    func csg(_ operation: CSGOperation, _ other: Mesh, options: CSGOptions = .init()) -> Mesh {
        if faceCount == 0 || other.faceCount == 0 {
            switch operation {
            case .union:
                return faceCount == 0 ? other : self

            case .intersection:
                return Mesh(positions: [], faces: [[Int]]())

            case .difference:
                return self
            }
        }
        guard let p = try? BooleanMesh(mesh: self), let q = try? BooleanMesh(mesh: other) else {
            return Mesh(positions: [], faces: [[Int]]())
        }
        var result = BooleanAssembler(p, q, operation: operation.booleanOperation)
            .assemble()
            .triangulated()
            .removingDegenerates()
            .toMesh(attributesFrom: p, q, invertQ: operation == .difference)
        if options.mergeCoplanar, result.cornerAttributes.cornerCount == 0 {
            result = result.mergingCoplanarFaces(angleTolerance: options.coplanarAngleTolerance, distanceTolerance: options.coplanarDistanceTolerance)
        }
        if !options.attributes.isEmpty {
            result.applyAttributes(options.attributes)
        }
        return result
    }
}

/// Post-processing and tolerances for mesh CSG.
///
/// The robust Boolean itself needs no tolerances: its precision comes from the inputs'
/// bounding boxes, and exact ties are broken symbolically.
public struct CSGOptions: Sendable {
    /// Merge adjacent coplanar triangles back into n-gons. Skipped when the result carries
    /// per-corner attributes, because merging would drop them.
    public var mergeCoplanar: Bool
    /// Maximum angle (radians) between normals for faces to count as coplanar.
    public var coplanarAngleTolerance: Float
    /// Maximum distance between planes for faces to count as coplanar.
    public var coplanarDistanceTolerance: Float
    /// Attributes to derive on the result (for example `.flatNormals`), replacing those
    /// interpolated from the inputs.
    public var attributes: MeshAttributes

    /// Creates options. The defaults match `union`/`intersection`/`difference` without arguments.
    public init(mergeCoplanar: Bool = true, coplanarAngleTolerance: Float = 1e-4, coplanarDistanceTolerance: Float = 1e-4, attributes: MeshAttributes = []) {
        self.mergeCoplanar = mergeCoplanar
        self.coplanarAngleTolerance = coplanarAngleTolerance
        self.coplanarDistanceTolerance = coplanarDistanceTolerance
        self.attributes = attributes
    }
}
