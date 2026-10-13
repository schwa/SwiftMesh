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
    ///   - weldTolerance: Used only when CSG is applied to triangle soups; see ``CSGOptions/weldTolerance``.
    /// - Returns: A new mesh representing the combined volume.
    func union(_ other: Mesh, mergeCoplanar: Bool = true, weldTolerance: Float = 1e-2) -> Mesh {
        csg(.union, other, options: CSGOptions(weldTolerance: weldTolerance, mergeCoplanar: mergeCoplanar))
    }

    /// Returns the CSG intersection of this mesh with another (A ∩ B).
    ///
    /// See ``csg(_:_:options:)`` for how the result is computed.
    ///
    /// - Parameters:
    ///   - other: The mesh to intersect with.
    ///   - mergeCoplanar: Merge adjacent coplanar triangles of the result back into n-gons
    ///     (only when the result has no attributes; see ``CSGOptions/mergeCoplanar``).
    ///   - weldTolerance: Used only when CSG is applied to triangle soups; see ``CSGOptions/weldTolerance``.
    /// - Returns: A new mesh containing only the shared volume.
    func intersection(_ other: Mesh, mergeCoplanar: Bool = true, weldTolerance: Float = 1e-2) -> Mesh {
        csg(.intersection, other, options: CSGOptions(weldTolerance: weldTolerance, mergeCoplanar: mergeCoplanar))
    }

    /// Returns the CSG difference of this mesh minus another (A − B).
    ///
    /// See ``csg(_:_:options:)`` for how the result is computed.
    ///
    /// - Parameters:
    ///   - other: The mesh volume to subtract.
    ///   - mergeCoplanar: Merge adjacent coplanar triangles of the result back into n-gons
    ///     (only when the result has no attributes; see ``CSGOptions/mergeCoplanar``).
    ///   - weldTolerance: Used only when CSG is applied to triangle soups; see ``CSGOptions/weldTolerance``.
    /// - Returns: A new mesh with the other's volume carved out.
    func difference(_ other: Mesh, mergeCoplanar: Bool = true, weldTolerance: Float = 1e-2) -> Mesh {
        csg(.difference, other, options: CSGOptions(weldTolerance: weldTolerance, mergeCoplanar: mergeCoplanar))
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
    /// - Returns: The result, or an empty mesh if either input is not a closed manifold.
    func csg(_ operation: CSGOperation, _ other: Mesh, options: CSGOptions = .init()) -> Mesh {
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
    /// Maximum distance for merging vertices when CSG is applied to ``TriangleSoup`` inputs,
    /// which must be welded into closed meshes first. Not used for ``Mesh`` inputs.
    public var weldTolerance: Float
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
    public init(weldTolerance: Float = 1e-2, mergeCoplanar: Bool = true, coplanarAngleTolerance: Float = 1e-4, coplanarDistanceTolerance: Float = 1e-4, attributes: MeshAttributes = []) {
        self.weldTolerance = weldTolerance
        self.mergeCoplanar = mergeCoplanar
        self.coplanarAngleTolerance = coplanarAngleTolerance
        self.coplanarDistanceTolerance = coplanarDistanceTolerance
        self.attributes = attributes
    }
}

// MARK: - TriangleSoup CSG

public extension TriangleSoup {
    /// Performs a CSG boolean operation combining this soup with another.
    ///
    /// Both soups are welded (positions within 1e-5) into meshes, which must then be
    /// closed manifolds, and combined with the robust Boolean (see `Mesh.csg(_:_:options:)`).
    ///
    /// - Parameters:
    ///   - operation: The boolean operation to perform.
    ///   - other: The second operand.
    /// - Returns: The result as a soup, or an empty soup if a welded input is not a closed manifold.
    func csg(_ operation: CSGOperation, _ other: TriangleSoup) -> TriangleSoup {
        guard !triangles.isEmpty, !other.triangles.isEmpty else {
            switch operation {
            case .union:
                return triangles.isEmpty ? other : self

            case .intersection:
                return Self()

            case .difference:
                return self
            }
        }
        let result = toMesh().csg(operation, other.toMesh(), options: CSGOptions(mergeCoplanar: false))
        return TriangleSoup(mesh: result)
    }

    /// Returns the union of this soup with another (A ∪ B).
    ///
    /// - Parameter other: The second operand.
    /// - Returns: A new triangle soup representing the union.
    func union(_ other: TriangleSoup) -> TriangleSoup {
        csg(.union, other)
    }

    /// Returns the intersection of this soup with another (A ∩ B).
    ///
    /// - Parameter other: The second operand.
    /// - Returns: A new triangle soup representing the intersection.
    func intersection(_ other: TriangleSoup) -> TriangleSoup {
        csg(.intersection, other)
    }

    /// Returns the difference of this soup minus another (A − B).
    ///
    /// - Parameter other: The volume to subtract.
    /// - Returns: A new triangle soup with the other's volume carved out.
    func difference(_ other: TriangleSoup) -> TriangleSoup {
        csg(.difference, other)
    }
}
