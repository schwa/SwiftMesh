import simd

/// An error produced by a `BinPacker`.
public enum BinPackingError: Error, Sendable {
    /// The packer ran out of space before placing all items.
    case outOfSpace
}

/// An item to pack: a caller-provided identifier and a size.
public struct PackingItem<ID: Hashable & Sendable, Scalar: RectScalar>: Hashable, Sendable {
    public var id: ID
    public var size: SIMD2<Scalar>

    public init(id: ID, size: SIMD2<Scalar>) {
        self.id = id
        self.size = size
    }
}

/// The result of packing a single item.
public struct PackedRect<ID: Hashable & Sendable, Scalar: RectScalar>: Hashable, Sendable {
    /// The caller-provided identifier of the input item.
    public var id: ID
    /// The placed rectangle in bin coordinates.
    public var rect: Rect<Scalar>
    /// Whether the item was rotated 90° to fit.
    public var rotated: Bool

    public init(id: ID, rect: Rect<Scalar>, rotated: Bool) {
        self.id = id
        self.rect = rect
        self.rotated = rotated
    }
}

/// The aggregate result of a packing operation.
public struct PackingResult<ID: Hashable & Sendable, Scalar: RectScalar>: Sendable {
    /// Successfully placed items, in the order they were placed.
    public var placements: [PackedRect<ID, Scalar>]
    /// IDs of input items that could not be placed.
    public var unplaced: [ID]
    /// The bin size used.
    public var binSize: SIMD2<Scalar>

    /// Lookup by id (O(n) on first access; cached afterwards).
    private var index: [ID: Int]

    public init(placements: [PackedRect<ID, Scalar>], unplaced: [ID], binSize: SIMD2<Scalar>) {
        self.placements = placements
        self.unplaced = unplaced
        self.binSize = binSize
        var index: [ID: Int] = [:]
        index.reserveCapacity(placements.count)
        for (i, p) in placements.enumerated() {
            index[p.id] = i
        }
        self.index = index
    }

    public var allPlaced: Bool { unplaced.isEmpty }

    /// Look up a placement by its caller-provided id. Returns `nil` if the item was not placed.
    public subscript(id: ID) -> PackedRect<ID, Scalar>? {
        guard let i = index[id] else {
            return nil
        }
        return placements[i]
    }
}
