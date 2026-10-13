import simd

/// A 2D bin packer implementing the MaxRects algorithm by Jukka Jylänki.
///
/// MaxRects maintains a list of maximal free rectangles and, for each item, picks the
/// free rectangle that scores best under a chosen heuristic. After placing the item,
/// any free rectangles that intersect it are split, and redundant rectangles are pruned.
///
/// Reference: "A Thousand Ways to Pack the Bin" — Jukka Jylänki (2010).
package struct MaxRectsPacker<Scalar: RectScalar> {
    /// Heuristics for choosing which free rectangle a new item is placed into.
    package enum Heuristic: Sendable {
        /// Best Short Side Fit — minimise the shorter leftover side. Generally a good default.
        case bestShortSideFit
        /// Best Long Side Fit — minimise the longer leftover side.
        case bestLongSideFit
        /// Best Area Fit — minimise leftover area in the chosen free rectangle.
        case bestAreaFit
        /// Bottom-Left — place at the lowest y, ties broken by lowest x.
        case bottomLeft
    }

    /// The bin's width and height.
    package let binSize: SIMD2<Scalar>
    /// Whether items may be rotated 90° when that fits better. See `PackedRect.rotated`.
    package let allowRotation: Bool
    /// Minimum gap to leave between placed items. Items may still touch the bin border with no padding.
    package let padding: Scalar
    /// How a free rectangle is chosen for each item. Changing it affects later `pack(_:)` calls.
    package var heuristic: Heuristic

    private var freeRects: [Rect<Scalar>]

    /// Creates a packer over an empty bin.
    package init(binSize: SIMD2<Scalar>, allowRotation: Bool = true, padding: Scalar = .zero, heuristic: Heuristic = .bestShortSideFit) {
        self.binSize = binSize
        self.allowRotation = allowRotation
        self.padding = padding
        self.heuristic = heuristic
        self.freeRects = [Rect(origin: SIMD2(repeating: .zero), size: binSize)]
    }

    /// Reset the packer to an empty bin.
    package mutating func reset() {
        freeRects = [Rect(origin: SIMD2(repeating: .zero), size: binSize)]
    }

    /// Places items in order into the remaining free space.
    ///
    /// Items that don't fit are reported in `PackingResult.unplaced` rather than failing
    /// the whole call. Space used by earlier calls stays used until ``reset()``.
    package mutating func pack<ID: Hashable & Sendable>(_ items: [PackingItem<ID, Scalar>]) -> PackingResult<ID, Scalar> {
        var placements: [PackedRect<ID, Scalar>] = []
        var unplaced: [ID] = []
        placements.reserveCapacity(items.count)

        for item in items {
            if let placed = placeOne(size: item.size) {
                placements.append(PackedRect(id: item.id, rect: placed.rect, rotated: placed.rotated))
            } else {
                unplaced.append(item.id)
            }
        }

        return PackingResult(placements: placements, unplaced: unplaced, binSize: binSize)
    }

    /// Convenience: pack sizes identified by their array index.
    package mutating func pack(_ sizes: [SIMD2<Scalar>]) -> PackingResult<Int, Scalar> {
        pack(sizes.enumerated().map { PackingItem(id: $0.offset, size: $0.element) })
    }

    // MARK: - Core

    private struct Placement {
        var rect: Rect<Scalar>
        var rotated: Bool
        var score1: Scalar
        var score2: Scalar
    }

    private mutating func placeOne(size: SIMD2<Scalar>) -> Placement? {
        var best: Placement?

        for free in freeRects {
            // Try un-rotated.
            if free.size.x >= size.x, free.size.y >= size.y {
                let candidate = makePlacement(free: free, size: size, rotated: false)
                if best == nil || isBetter(candidate, than: best!) {
                    best = candidate
                }
            }
            // Try rotated.
            if allowRotation, size.x != size.y, free.size.x >= size.y, free.size.y >= size.x {
                let rotatedSize = SIMD2<Scalar>(size.y, size.x)
                let candidate = makePlacement(free: free, size: rotatedSize, rotated: true)
                if best == nil || isBetter(candidate, than: best!) {
                    best = candidate
                }
            }
        }

        guard let placement = best else {
            return nil
        }

        // Split any free rectangles that intersect the new placement (inflated by padding
        // on all sides), then prune. Inflation outside the bin is harmless because the
        // split logic naturally clips strips with non-positive width/height.
        let inflated: Rect<Scalar>
        if padding == .zero {
            inflated = placement.rect
        } else {
            inflated = Rect(
                origin: SIMD2(placement.rect.minX - padding, placement.rect.minY - padding),
                size: SIMD2(placement.rect.size.x + padding + padding, placement.rect.size.y + padding + padding)
            )
        }
        var newFree: [Rect<Scalar>] = []
        var isNew: [Bool] = []
        newFree.reserveCapacity(freeRects.count * 2)
        isNew.reserveCapacity(freeRects.count * 2)
        for free in freeRects {
            let before = newFree.count
            if splitFreeRect(free: free, used: inflated, into: &newFree) {
                isNew += repeatElement(true, count: newFree.count - before)
            } else {
                newFree.append(free)
                isNew.append(false)
            }
        }
        freeRects = newFree
        pruneFreeRects(isNew: isNew)

        return placement
    }

    private func makePlacement(free: Rect<Scalar>, size: SIMD2<Scalar>, rotated: Bool) -> Placement {
        let rect = Rect(origin: free.origin, size: size)
        let leftoverX = free.size.x - size.x
        let leftoverY = free.size.y - size.y
        switch heuristic {
        case .bestShortSideFit:
            let shortSide = min(leftoverX, leftoverY)
            let longSide = max(leftoverX, leftoverY)
            return Placement(rect: rect, rotated: rotated, score1: shortSide, score2: longSide)

        case .bestLongSideFit:
            let shortSide = min(leftoverX, leftoverY)
            let longSide = max(leftoverX, leftoverY)
            return Placement(rect: rect, rotated: rotated, score1: longSide, score2: shortSide)

        case .bestAreaFit:
            let area = free.size.x * free.size.y - size.x * size.y
            let shortSide = min(leftoverX, leftoverY)
            return Placement(rect: rect, rotated: rotated, score1: area, score2: shortSide)

        case .bottomLeft:
            return Placement(rect: rect, rotated: rotated, score1: rect.maxY, score2: rect.minX)
        }
    }

    private func isBetter(_ a: Placement, than b: Placement) -> Bool {
        if a.score1 != b.score1 {
            return a.score1 < b.score1
        }
        return a.score2 < b.score2
    }

    /// If `used` intersects `free`, split `free` into up to 4 maximal subrectangles
    /// and append them to `out`. Returns `true` if a split occurred.
    private func splitFreeRect(free: Rect<Scalar>, used: Rect<Scalar>, into out: inout [Rect<Scalar>]) -> Bool {
        // Quick reject: no overlap.
        if used.minX >= free.maxX || used.maxX <= free.minX || used.minY >= free.maxY || used.maxY <= free.minY {
            return false
        }

        // Left strip.
        if used.minX > free.minX, used.minX < free.maxX {
            out.append(Rect(x: free.minX, y: free.minY, width: used.minX - free.minX, height: free.size.y))
        }
        // Right strip.
        if used.maxX < free.maxX, used.maxX > free.minX {
            out.append(Rect(x: used.maxX, y: free.minY, width: free.maxX - used.maxX, height: free.size.y))
        }
        // Bottom strip.
        if used.minY > free.minY, used.minY < free.maxY {
            out.append(Rect(x: free.minX, y: free.minY, width: free.size.x, height: used.minY - free.minY))
        }
        // Top strip.
        if used.maxY < free.maxY, used.maxY > free.minY {
            out.append(Rect(x: free.minX, y: used.maxY, width: free.size.x, height: free.maxY - used.maxY))
        }

        return true
    }

    /// Remove any free rectangle contained by another; among equal rectangles the last survives.
    ///
    /// Rectangles untouched by the last split were already mutually non-contained, so only
    /// pairs involving a new rectangle need checking (Jylänki's incremental pruning).
    /// Survivors keep their order, so placements match the all-pairs version exactly.
    private mutating func pruneFreeRects(isNew: [Bool]) {
        let count = freeRects.count
        var drop = [Bool](repeating: false, count: count)
        for i in 0..<count where isNew[i] {
            for j in 0..<count where j != i {
                if freeRects[j].contains(freeRects[i]), freeRects[j] != freeRects[i] || j > i {
                    drop[i] = true
                }
                // Old rectangles can only be swallowed by new ones.
                if !isNew[j], freeRects[i].contains(freeRects[j]), freeRects[j] != freeRects[i] || i > j {
                    drop[j] = true
                }
            }
        }
        var kept: [Rect<Scalar>] = []
        kept.reserveCapacity(count)
        for index in 0..<count where !drop[index] {
            kept.append(freeRects[index])
        }
        freeRects = kept
    }
}
