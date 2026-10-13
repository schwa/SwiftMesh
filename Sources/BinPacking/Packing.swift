import simd

/// An error produced by a `BinPacker`.
package enum BinPackingError: Error, Sendable {
    /// The packer ran out of space before placing all items.
    case outOfSpace
}

/// An item to pack: a caller-provided identifier and a size.
package struct PackingItem<ID: Hashable & Sendable, Scalar: RectScalar>: Hashable, Sendable {
    /// Identifies the item in the `PackingResult`.
    package var id: ID
    /// The item's width and height before any rotation.
    package var size: SIMD2<Scalar>

    package init(id: ID, size: SIMD2<Scalar>) {
        self.id = id
        self.size = size
    }
}

/// The result of packing a single item.
package struct PackedRect<ID: Hashable & Sendable, Scalar: RectScalar>: Hashable, Sendable {
    /// The caller-provided identifier of the input item.
    package var id: ID
    /// The placed rectangle in bin coordinates.
    package var rect: Rect<Scalar>
    /// Whether the item was rotated 90° to fit.
    package var rotated: Bool

    /// Creates a placement. Packers produce these; callers rarely need to.
    package init(id: ID, rect: Rect<Scalar>, rotated: Bool) {
        self.id = id
        self.rect = rect
        self.rotated = rotated
    }
}

/// The aggregate result of a packing operation.
package struct PackingResult<ID: Hashable & Sendable, Scalar: RectScalar>: Sendable {
    /// Successfully placed items, in the order they were placed.
    package var placements: [PackedRect<ID, Scalar>]
    /// IDs of input items that could not be placed.
    package var unplaced: [ID]
    /// The bin size used.
    package var binSize: SIMD2<Scalar>

    /// Lookup by id (O(n) on first access; cached afterwards).
    private var index: [ID: Int]

    /// Creates a result and indexes placements by id.
    package init(placements: [PackedRect<ID, Scalar>], unplaced: [ID], binSize: SIMD2<Scalar>) {
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

    /// Whether every input item was placed.
    package var allPlaced: Bool { unplaced.isEmpty }

    /// Look up a placement by its caller-provided id. Returns `nil` if the item was not placed.
    package subscript(id: ID) -> PackedRect<ID, Scalar>? {
        guard let i = index[id] else {
            return nil
        }
        return placements[i]
    }
}
