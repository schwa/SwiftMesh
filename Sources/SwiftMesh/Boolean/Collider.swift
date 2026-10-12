// Ported from Manifold (https://github.com/elalish/manifold): src/collider.h, src/sort.cpp
// (GetFaceBoxMorton), include/manifold/common.h (Box). Copyright 2021 The Manifold Authors.
// Licensed under the Apache License, Version 2.0; see NOTICE.

import simd

/// Axis-aligned box in Double (Manifold's `Box`). Empty boxes have min = +inf, max = -inf.
package struct BooleanBox: Sendable, Equatable {
    var min = SIMD3<Double>(repeating: .infinity)
    var max = SIMD3<Double>(repeating: -.infinity)

    package init() {}

    package init(_ a: SIMD3<Double>, _ b: SIMD3<Double>) {
        min = simd_min(a, b)
        max = simd_max(a, b)
    }

    var isEmpty: Bool { min.x == .infinity }

    mutating func union(_ point: SIMD3<Double>) {
        min = simd_min(min, point)
        max = simd_max(max, point)
    }

    func union(_ other: Self) -> Self {
        var result = self
        result.min = simd_min(min, other.min)
        result.max = simd_max(max, other.max)
        return result
    }

    /// Closed-interval overlap in 3D.
    func overlaps(_ other: Self) -> Bool {
        min.x <= other.max.x && min.y <= other.max.y && min.z <= other.max.z &&
            max.x >= other.min.x && max.y >= other.min.y && max.z >= other.min.z
    }

    /// Whether the point projects inside the box's XY extent (the Boolean's +z shadow query).
    func overlapsXY(_ point: SIMD3<Double>) -> Bool {
        point.x <= max.x && point.x >= min.x && point.y <= max.y && point.y >= min.y
    }
}

/// A radix-tree BVH over leaf boxes, built from Morton codes (Manifold's `Collider`).
///
/// Leaves are kept in Morton order internally; queries report the original leaf index.
package struct Collider: Sendable {
    // Node numbering as in Manifold: even nodes are leaves, odd nodes internal, root is 1.
    private var nodeBox: [BooleanBox] = []
    private var nodeParent: [Int] = []
    private var internalChildren: [(Int, Int)] = []
    /// Sorted leaf -> original leaf index.
    private var leafItem: [Int] = []

    private static let root = 1
    private static func isLeaf(_ node: Int) -> Bool { node.isMultiple(of: 2) }
    private static func node2Internal(_ node: Int) -> Int { (node - 1) / 2 }
    private static func internal2Node(_ index: Int) -> Int { index * 2 + 1 }
    private static func node2Leaf(_ node: Int) -> Int { node / 2 }
    private static func leaf2Node(_ leaf: Int) -> Int { leaf * 2 }

    var leafCount: Int { leafItem.count }

    init(boxes: [BooleanBox], mortonCodes: [UInt32]) {
        precondition(boxes.count == mortonCodes.count, "boxes and Morton codes must be the same length")
        guard !boxes.isEmpty else {
            return
        }
        leafItem = boxes.indices.sorted { mortonCodes[$0] != mortonCodes[$1] ? mortonCodes[$0] < mortonCodes[$1] : $0 < $1 }
        let sortedMorton = leafItem.map { mortonCodes[$0] }
        let nodeCount = 2 * boxes.count - 1
        nodeBox = [BooleanBox](repeating: BooleanBox(), count: nodeCount)
        nodeParent = [Int](repeating: -1, count: nodeCount)
        internalChildren = [(Int, Int)](repeating: (-1, -1), count: boxes.count - 1)
        for index in 0..<internalChildren.count {
            createRadixTreeNode(index, morton: sortedMorton)
        }
        for (leaf, item) in leafItem.enumerated() {
            nodeBox[Self.leaf2Node(leaf)] = boxes[item]
        }
        // A single leaf has no internal nodes (Manifold never builds this case).
        if boxes.count > 1 {
            buildInternalBoxes()
        }
    }

    /// The box around everything.
    var boundingBox: BooleanBox {
        guard !nodeBox.isEmpty else {
            return BooleanBox()
        }
        return leafItem.count == 1 ? nodeBox[0] : nodeBox[Self.root]
    }

    /// Manifold's `MortonCode`: 30-bit interleaved code of `position` within `bounds`.
    static func mortonCode(_ position: SIMD3<Double>, in bounds: BooleanBox) -> UInt32 {
        var xyz = (position - bounds.min) / (bounds.max - bounds.min)
        xyz = simd_min(SIMD3(repeating: 1_023), simd_max(.zero, 1_024 * xyz))
        // Degenerate (flat) bounds divide by zero; treat NaN as 0.
        let x = spreadBits3(UInt32(xyz.x.isNaN ? 0 : xyz.x))
        let y = spreadBits3(UInt32(xyz.y.isNaN ? 0 : xyz.y))
        let z = spreadBits3(UInt32(xyz.z.isNaN ? 0 : xyz.z))
        return x * 4 + y * 2 + z
    }

    private static func spreadBits3(_ value: UInt32) -> UInt32 {
        var v = value
        v = 0xFF00_00FF & (v &* 0x0001_0001)
        v = 0x0F00_F00F & (v &* 0x0000_0101)
        v = 0xC30C_30C3 & (v &* 0x0000_0011)
        v = 0x4924_9249 & (v &* 0x0000_0005)
        return v
    }

    // MARK: Queries

    /// Calls `found(leaf)` for every leaf whose box overlaps `query` (3D, closed intervals).
    package func forEachOverlap(_ query: BooleanBox, _ found: (Int) -> Void) {
        guard !query.isEmpty else {
            return
        }
        traverse(overlaps: { $0.overlaps(query) }, found)
    }

    /// Calls `found(leaf)` for every leaf whose box contains `point` in XY projection.
    func forEachOverlapXY(_ point: SIMD3<Double>, _ found: (Int) -> Void) {
        traverse(overlaps: { $0.overlapsXY(point) }, found)
    }

    /// Manifold's `FindCollision`: iterative depth-first search with a small stack.
    private func traverse(overlaps: (BooleanBox) -> Bool, _ found: (Int) -> Void) {
        guard !leafItem.isEmpty else {
            return
        }
        if leafItem.count == 1 {
            if overlaps(nodeBox[0]) {
                found(leafItem[0])
            }
            return
        }
        var stack: [Int] = []
        stack.reserveCapacity(64)
        var node = Self.root
        while true {
            let (child1, child2) = internalChildren[Self.node2Internal(node)]
            let traverse1 = record(child1, overlaps: overlaps, found)
            let traverse2 = record(child2, overlaps: overlaps, found)
            if !traverse1, !traverse2 {
                guard let saved = stack.popLast() else {
                    break
                }
                node = saved
            } else {
                node = traverse1 ? child1 : child2
                if traverse1, traverse2 {
                    stack.append(child2)
                }
            }
        }
    }

    /// Reports a leaf hit; returns whether to descend into an internal node.
    private func record(_ node: Int, overlaps: (BooleanBox) -> Bool, _ found: (Int) -> Void) -> Bool {
        let hit = overlaps(nodeBox[node])
        if hit, Self.isLeaf(node) {
            found(leafItem[Self.node2Leaf(node)])
        }
        return hit && !Self.isLeaf(node)
    }

    // MARK: Construction (Manifold's CreateRadixTree and BuildInternalBoxes)

    private func prefixLength(_ a: UInt32, _ b: UInt32) -> Int {
        (a ^ b).leadingZeroBitCount
    }

    private func prefixLength(_ i: Int, _ j: Int, morton: [UInt32]) -> Int {
        guard j >= 0, j < morton.count else {
            return -1
        }
        // Equal codes are disambiguated by index.
        return morton[i] == morton[j] ? 32 + prefixLength(UInt32(i), UInt32(j)) : prefixLength(morton[i], morton[j])
    }

    private func rangeEnd(_ i: Int, morton: [UInt32]) -> Int {
        var direction = prefixLength(i, i + 1, morton: morton) - prefixLength(i, i - 1, morton: morton)
        direction = direction > 0 ? 1 : (direction < 0 ? -1 : 0)
        let commonPrefix = prefixLength(i, i - direction, morton: morton)
        var maxLength = 128
        while prefixLength(i, i + direction * maxLength, morton: morton) > commonPrefix {
            maxLength *= 4
        }
        var length = 0
        var step = maxLength / 2
        while step > 0 {
            if prefixLength(i, i + direction * (length + step), morton: morton) > commonPrefix {
                length += step
            }
            step /= 2
        }
        return i + direction * length
    }

    private func findSplit(_ first: Int, _ last: Int, morton: [UInt32]) -> Int {
        let commonPrefix = prefixLength(first, last, morton: morton)
        var split = first
        var step = last - first
        repeat {
            step = (step + 1) >> 1
            let newSplit = split + step
            if newSplit < last, prefixLength(first, newSplit, morton: morton) > commonPrefix {
                split = newSplit
            }
        } while step > 1
        return split
    }

    private mutating func createRadixTreeNode(_ index: Int, morton: [UInt32]) {
        var first = index
        var last = rangeEnd(first, morton: morton)
        if first > last {
            swap(&first, &last)
        }
        var split = findSplit(first, last, morton: morton)
        let child1 = split == first ? Self.leaf2Node(split) : Self.internal2Node(split)
        split += 1
        let child2 = split == last ? Self.leaf2Node(split) : Self.internal2Node(split)
        internalChildren[index] = (child1, child2)
        let node = Self.internal2Node(index)
        nodeParent[child1] = node
        nodeParent[child2] = node
    }

    private mutating func buildInternalBoxes() {
        // The second child to arrive at an internal node computes its box, so each is built once.
        var arrivals = [Int](repeating: 0, count: internalChildren.count)
        for leaf in 0..<leafItem.count {
            var node = Self.leaf2Node(leaf)
            repeat {
                node = nodeParent[node]
                let index = Self.node2Internal(node)
                arrivals[index] += 1
                if arrivals[index] == 1 {
                    break
                }
                let (child1, child2) = internalChildren[index]
                nodeBox[node] = nodeBox[child1].union(nodeBox[child2])
            } while node != Self.root
        }
    }
}

extension BooleanMesh {
    /// A collider over this mesh's triangles; leaf indices are triangle indices
    /// (Manifold's `GetFaceBoxMorton` + `Collider`).
    package func makeFaceCollider() -> Collider {
        var bounds = BooleanBox()
        bounds.min = boundsMin
        bounds.max = boundsMax
        var boxes = [BooleanBox](repeating: BooleanBox(), count: numTri)
        var codes = [UInt32](repeating: 0, count: numTri)
        for triangle in 0..<numTri {
            var center = SIMD3<Double>.zero
            for corner in 0..<3 {
                let position = vertPos[halfedges[3 * triangle + corner].startVert]
                center += position
                boxes[triangle].union(position)
            }
            codes[triangle] = Collider.mortonCode(center / 3, in: bounds)
        }
        return Collider(boxes: boxes, mortonCodes: codes)
    }
}
