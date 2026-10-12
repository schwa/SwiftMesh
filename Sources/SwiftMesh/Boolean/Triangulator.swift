// Ported from Manifold (https://github.com/elalish/manifold): src/polygon.cpp (EarClip,
// IsConvex, TriangulateConvex), src/tree2d.h/.cpp (2D tree), src/utils.h (CCW).
// Copyright 2021 The Manifold Authors. Licensed under the Apache License, Version 2.0; see NOTICE.

import simd

/// A polygon vertex: 2D position plus the index of the mesh vertex it stands for.
package struct PolyVert: Sendable, Equatable {
    package var pos: SIMD2<Double>
    package var idx: Int

    package init(pos: SIMD2<Double>, idx: Int) {
        self.pos = pos
        self.idx = idx
    }
}

/// Manifold's `CCW`: 1 if p0, p1, p2 turn counter-clockwise, -1 if clockwise, 0 if within `tolerance`.
func ccw(_ p0: SIMD2<Double>, _ p1: SIMD2<Double>, _ p2: SIMD2<Double>, _ tolerance: Double) -> Int {
    let v1 = p1 - p0
    let v2 = p2 - p0
    let area = v1.x * v2.y - v1.y * v2.x
    let base2 = max(simd_dot(v1, v1), simd_dot(v2, v2))
    if area * area * 4 <= base2 * tolerance * tolerance {
        return 0
    }
    return area > 0 ? 1 : -1
}

private func determinant2x2(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
    a.x * b.y - a.y * b.x
}

private func safeNormalize(_ v: SIMD2<Double>) -> SIMD2<Double> {
    let normalized = simd_normalize(v)
    return normalized.x.isFinite ? normalized : .zero
}

/// Axis-aligned 2D rectangle (Manifold's `Rect`). Empty: min = +inf, max = -inf.
private struct Rect2 {
    var min = SIMD2<Double>(repeating: .infinity)
    var max = SIMD2<Double>(repeating: -.infinity)

    mutating func union(_ p: SIMD2<Double>) {
        min = simd_min(min, p)
        max = simd_max(max, p)
    }

    func contains(_ p: SIMD2<Double>) -> Bool {
        p.x >= min.x && p.y >= min.y && max.x >= p.x && max.y >= p.y
    }

    func overlaps(_ other: Self) -> Bool {
        min.x <= other.max.x && min.y <= other.max.y && max.x >= other.min.x && max.y >= other.min.y
    }

    var size: SIMD2<Double> { max - min }

    var scale: Double {
        let absMax = simd_max(simd_abs(min), simd_abs(max))
        return Swift.max(absMax.x, absMax.y)
    }
}

/// Triangulates ε-valid polygons (Manifold's `TriangulateIdx`).
///
/// Polygons are wound counter-clockwise; clockwise contours are holes. Invalid input may
/// overlap but still yields a manifold triangulation that follows the input edge directions.
///
/// - Parameters:
///   - epsilon: The input's uncertainty. Negative uses the bounding-box scale times 1e-12.
///   - allowConvex: Use a fast alternating fan when every polygon is convex.
/// - Returns: Triangles as mesh vertex indices (`PolyVert.idx`).
package func triangulate(_ polygons: [[PolyVert]], epsilon: Double, allowConvex: Bool = true) -> [SIMD3<Int>] {
    let polygons = polygons.filter { !$0.isEmpty }
    if allowConvex, isConvex(polygons, epsilon: epsilon) {
        return triangulateConvex(polygons)
    }
    var clipper = EarClip()
    return clipper.triangulate(polygons, epsilon: epsilon)
}

/// Manifold's `IsConvex`: no reflex vertices; colinear and zero-length edges count as reflex.
private func isConvex(_ polygons: [[PolyVert]], epsilon: Double) -> Bool {
    for polygon in polygons {
        let firstEdge = polygon[0].pos - polygon[polygon.count - 1].pos
        var lastEdge = simd_normalize(firstEdge)
        for v in polygon.indices {
            let edge = v + 1 < polygon.count ? polygon[v + 1].pos - polygon[v].pos : firstEdge
            let det = determinant2x2(lastEdge, edge)
            if det <= 0 || (abs(det) < epsilon && simd_dot(lastEdge, edge) < 0) {
                return false
            }
            lastEdge = simd_normalize(edge)
        }
    }
    return true
}

/// Manifold's `TriangulateConvex`: alternates sides instead of a fan to avoid high-valence vertices.
private func triangulateConvex(_ polygons: [[PolyVert]]) -> [SIMD3<Int>] {
    var triangles: [SIMD3<Int>] = []
    for polygon in polygons {
        var i = 0
        var k = polygon.count - 1
        var right = true
        while i + 1 < k {
            let j = right ? i + 1 : k - 1
            triangles.append(SIMD3(polygon[i].idx, polygon[j].idx, polygon[k].idx))
            if right {
                i = j
            } else {
                k = j
            }
            right.toggle()
        }
    }
    return triangles
}

// MARK: - 2D tree (Manifold's tree2d)

/// Sorts `points` in place into an implicit alternating-axis k-d tree.
private func buildTwoDTree(_ points: inout [PolyVert]) {
    guard points.count > 8 else {
        return
    }
    func build(_ range: Range<Int>, sortX: Bool) {
        // Stable sort of the slice, as Manifold's stable_sort.
        let sorted = points[range].enumerated().sorted { a, b in
            let ka = sortX ? a.element.pos.x : a.element.pos.y
            let kb = sortX ? b.element.pos.x : b.element.pos.y
            return ka != kb ? ka < kb : a.offset < b.offset
        }.map(\.element)
        points.replaceSubrange(range, with: sorted)
        guard range.count >= 2 else {
            return
        }
        let middle = range.lowerBound + range.count / 2
        build(range.lowerBound..<middle, sortX: !sortX)
        build((middle + 1)..<range.upperBound, sortX: !sortX)
    }
    build(points.indices, sortX: true)
}

private func queryTwoDTree(_ points: [PolyVert], _ query: Rect2, _ found: (PolyVert) -> Void) {
    if points.count <= 8 {
        for point in points where query.contains(point.pos) {
            found(point)
        }
        return
    }
    var current = Rect2(min: SIMD2(repeating: -.infinity), max: SIMD2(repeating: .infinity))
    var level = 0
    var view = points.indices
    var stack: [(Rect2, Range<Int>, Int)] = []
    while true {
        if view.count <= 8 {
            for index in view where query.contains(points[index].pos) {
                found(points[index])
            }
            guard let (rect, saved, savedLevel) = stack.popLast() else {
                break
            }
            current = rect
            view = saved
            level = savedLevel
            continue
        }
        var left = current
        var right = current
        let middleIndex = view.lowerBound + view.count / 2
        let middle = points[middleIndex]
        if level.isMultiple(of: 2) {
            left.max.x = middle.pos.x
            right.min.x = middle.pos.x
        } else {
            left.max.y = middle.pos.y
            right.min.y = middle.pos.y
        }
        if query.contains(middle.pos) {
            found(middle)
        }
        let leftView = view.lowerBound..<middleIndex
        let rightView = (middleIndex + 1)..<view.upperBound
        if left.overlaps(query) {
            if right.overlaps(query) {
                stack.append((right, rightView, level + 1))
            }
            current = left
            view = leftView
        } else {
            current = right
            view = rightView
        }
        level += 1
    }
}

// MARK: - Ear clipping

/// Manifold's `EarClip`: ear clipping after Eberly, adjusted for ε-valid polygons. Sharpest
/// ears go first, and convexity is decided exhaustively when the first test is within ε.
private struct EarClip {
    /// A vertex in the circular doubly-linked list of remaining polygon vertices.
    struct Vert {
        var meshIndex: Int
        var cost: Double = 0
        var pos: SIMD2<Double>
        var rightDir: SIMD2<Double> = .zero
        var left = -1
        var right = -1
        /// Bumped whenever the vertex's queue entry changes; stale heap entries are skipped.
        var earVersion = 0
        var inQueue = false
    }

    struct QueueEntry {
        var cost: Double
        var sequence: Int
        var vert: Int
        var version: Int
    }

    private var polygon: [Vert] = []
    private var starts: [Int] = []
    private var holes: [Int] = []
    private var outers: [Int] = []
    private var simples: [Int] = []
    private var holeBox: [Int: Rect2] = [:]
    private var heap: [QueueEntry] = []
    private var sequence = 0
    private var colliderPoints: [PolyVert] = []
    private var colliderVerts: [Int] = []
    private var triangles: [SIMD3<Int>] = []
    private var bounds = Rect2()
    private var epsilon = 0.0

    private static let best = -Double.infinity

    mutating func triangulate(_ polygons: [[PolyVert]], epsilon: Double) -> [SIMD3<Int>] {
        self.epsilon = epsilon
        initialize(polygons)
        for v in polygon.indices {
            clipIfDegenerate(v)
        }
        for first in starts {
            findStart(first)
        }
        // Holes are processed right-most first (Manifold's MaxX multiset; stable for ties).
        let orderedHoles = holes.enumerated().sorted { a, b in
            polygon[a.element].pos.x != polygon[b.element].pos.x ? polygon[a.element].pos.x > polygon[b.element].pos.x : a.offset < b.offset
        }.map(\.element)
        for start in orderedHoles {
            cutKeyhole(start)
        }
        for start in simples {
            triangulatePoly(start)
        }
        return triangles
    }

    // MARK: Vert geometry

    private func isShort(_ v: Int, _ epsilon: Double) -> Bool {
        let edge = polygon[polygon[v].right].pos - polygon[v].pos
        return simd_dot(edge, edge) * 4 < epsilon * epsilon
    }

    /// Whether `vert` is on the inside of the edge from `tail` to `tail.right`, walking edges
    /// until the answer is clear beyond ε.
    private func insideEdge(_ vert: Int, tail: Int, _ epsilon: Double, toLeft: Bool) -> Bool {
        let p2 = epsilon * epsilon
        var nextL = polygon[polygon[vert].left].right
        var nextR = polygon[tail].right
        var center = tail
        var last = center
        let stop = toLeft ? polygon[vert].right : polygon[vert].left
        while nextL != nextR, tail != nextR, nextL != stop {
            let edgeL = polygon[nextL].pos - polygon[center].pos
            let l2 = simd_dot(edgeL, edgeL)
            if l2 <= p2 {
                nextL = toLeft ? polygon[nextL].left : polygon[nextL].right
                continue
            }
            let edgeR = polygon[nextR].pos - polygon[center].pos
            let r2 = simd_dot(edgeR, edgeR)
            if r2 <= p2 {
                nextR = polygon[nextR].right
                continue
            }
            let vecLR = polygon[nextR].pos - polygon[nextL].pos
            if simd_dot(vecLR, vecLR) <= p2 {
                last = center
                center = nextL
                nextL = toLeft ? polygon[nextL].left : polygon[nextL].right
                if nextL == nextR {
                    break
                }
                nextR = polygon[nextR].right
                continue
            }
            var convexity = ccw(polygon[nextL].pos, polygon[center].pos, polygon[nextR].pos, epsilon)
            if center != last {
                convexity += ccw(polygon[last].pos, polygon[center].pos, polygon[nextL].pos, epsilon) +
                    ccw(polygon[nextR].pos, polygon[center].pos, polygon[last].pos, epsilon)
            }
            if convexity != 0 {
                return convexity > 0
            }
            if l2 < r2 {
                center = nextL
                nextL = toLeft ? polygon[nextL].left : polygon[nextL].right
            } else {
                center = nextR
                nextR = polygon[nextR].right
            }
            last = center
        }
        // The whole polygon is degenerate; treat as convex.
        return true
    }

    private func isConvexVert(_ v: Int, _ epsilon: Double) -> Bool {
        ccw(polygon[polygon[v].left].pos, polygon[v].pos, polygon[polygon[v].right].pos, epsilon) >= 0
    }

    /// Unlike `!isConvexVert`, keeps walking until certain.
    private func isReflex(_ v: Int, _ epsilon: Double) -> Bool {
        let left = polygon[v].left
        return !insideEdge(left, tail: polygon[left].right, epsilon, toLeft: true)
    }

    /// The x on this edge at `start.y`, or NaN if the edge doesn't cross upward right of start.
    private func interpY2X(_ v: Int, _ start: SIMD2<Double>, onTop: Int, _ epsilon: Double) -> Double {
        let pos = polygon[v].pos
        let right = polygon[polygon[v].right].pos
        if abs(pos.y - start.y) <= epsilon {
            return right.y <= start.y + epsilon || onTop == 1 ? .nan : pos.x
        } else if pos.y < start.y - epsilon {
            if right.y > start.y + epsilon {
                return pos.x + (start.y - pos.y) * (right.x - pos.x) / (right.y - pos.y)
            } else if right.y < start.y - epsilon || onTop == -1 {
                return .nan
            }
            return right.x
        }
        return .nan
    }

    private func signedDistance(from v: Int, to test: Int, unit: SIMD2<Double>, _ epsilon: Double) -> Double {
        let pos = polygon[v].pos
        let d = determinant2x2(unit, polygon[test].pos - pos)
        if abs(d) < epsilon {
            let dR = determinant2x2(unit, polygon[polygon[test].right].pos - pos)
            if abs(dR) > epsilon {
                return dR
            }
            let dL = determinant2x2(unit, polygon[polygon[test].left].pos - pos)
            if abs(dL) > epsilon {
                return dL
            }
        }
        return d
    }

    private func cost(of v: Int, test: Int, openSide: SIMD2<Double>, _ epsilon: Double) -> Double {
        let left = polygon[v].left
        let sideCost = min(signedDistance(from: v, to: test, unit: polygon[v].rightDir, epsilon),
                           signedDistance(from: left, to: test, unit: polygon[left].rightDir, epsilon))
        let openCost = determinant2x2(openSide, polygon[test].pos - polygon[polygon[v].right].pos)
        return min(sideCost, openCost)
    }

    /// Checks this ear against nearby vertices. Below -ε is valid, above ε invalid; sharper
    /// ears and Delaunay-like ears score better.
    private func earCost(_ v: Int, _ epsilon: Double) -> Double {
        let vert = polygon[v]
        let left = polygon[vert.left]
        let right = polygon[vert.right]
        var openSide = left.pos - right.pos
        let center = 0.5 * (left.pos + right.pos)
        let scale = 4 / simd_dot(openSide, openSide)
        let radius = simd_length(openSide) / 2
        openSide = simd_normalize(openSide)

        var totalCost = simd_dot(left.rightDir, vert.rightDir) - 1 - epsilon
        if ccw(vert.pos, left.pos, right.pos, epsilon) == 0 {
            // Clip folded ears first.
            return totalCost
        }
        var earBox = Rect2(min: center - radius, max: center + radius)
        earBox.union(vert.pos)
        earBox.min -= epsilon
        earBox.max += epsilon

        queryTwoDTree(colliderPoints, earBox) { point in
            let test = colliderVerts[point.idx]
            let testIndex = polygon[test].meshIndex
            guard !isClipped(test), testIndex != vert.meshIndex, testIndex != left.meshIndex, testIndex != right.meshIndex else {
                return // duplicated verts are skipped
            }
            var testCost = cost(of: v, test: test, openSide: openSide, epsilon)
            if testCost < -epsilon {
                let diff = polygon[test].pos - center
                testCost = -epsilon - scale * simd_dot(diff, diff) // Delaunay cost
            }
            totalCost = max(totalCost, testCost)
        }
        return totalCost
    }

    // MARK: Circular list

    private mutating func link(_ left: Int, _ right: Int) {
        polygon[left].right = right
        polygon[right].left = left
        polygon[left].rightDir = safeNormalize(polygon[right].pos - polygon[left].pos)
    }

    /// A clipped vert's neighbors are linked past it, but it still points at them.
    private func isClipped(_ v: Int) -> Bool {
        polygon[polygon[v].right].left != v
    }

    /// Calls `body` on each un-clipped vert and returns an un-clipped vert, or nil if the
    /// polygon has collapsed to two points.
    @discardableResult
    private func loop(_ start: Int, _ body: (Int) -> Void) -> Int? {
        var first = start
        var v = first
        repeat {
            if isClipped(v) {
                // Move first to an un-clipped vert so the loop can terminate.
                first = polygon[polygon[v].right].left
                if !isClipped(first) {
                    v = first
                    if polygon[v].right == polygon[v].left {
                        return nil
                    }
                    body(v)
                }
            } else {
                if polygon[v].right == polygon[v].left {
                    return nil
                }
                body(v)
            }
            v = polygon[v].right
        } while v != first
        return v
    }

    private mutating func clipEar(_ ear: Int) {
        let left = polygon[ear].left
        let right = polygon[ear].right
        link(left, right)
        let l = polygon[left].meshIndex
        let m = polygon[ear].meshIndex
        let r = polygon[right].meshIndex
        // Skip topological degenerates from keyhole vertex duplication.
        if l != m, m != r, r != l {
            triangles.append(SIMD3(l, m, r))
        }
    }

    /// Clips ears that would make degenerate triangles, recursively, before keyholing.
    private mutating func clipIfDegenerate(_ ear: Int) {
        if isClipped(ear) || polygon[ear].left == polygon[ear].right {
            return
        }
        let left = polygon[polygon[ear].left].pos
        let pos = polygon[ear].pos
        let right = polygon[polygon[ear].right].pos
        if isShort(ear, epsilon) || (ccw(left, pos, right, epsilon) == 0 && simd_dot(left - pos, right - pos) > 0) {
            clipEar(ear)
            clipIfDegenerate(polygon[ear].left)
            clipIfDegenerate(polygon[ear].right)
        }
    }

    private mutating func initialize(_ polygons: [[PolyVert]]) {
        for poly in polygons {
            let first = polygon.count
            polygon.append(Vert(meshIndex: poly[0].idx, pos: poly[0].pos))
            bounds.union(poly[0].pos)
            starts.append(first)
            var last = first
            for vert in poly.dropFirst() {
                bounds.union(vert.pos)
                polygon.append(Vert(meshIndex: vert.idx, pos: vert.pos))
                let next = polygon.count - 1
                link(last, next)
                last = next
            }
            link(last, first)
        }
        if epsilon < 0 {
            epsilon = bounds.scale * BooleanMesh.relativePrecision
        }
    }

    /// Finds the right-most reflex start of each contour and classifies it as hole or outer.
    private mutating func findStart(_ first: Int) {
        let origin = polygon[first].pos
        var start = first
        var maxX = -Double.infinity
        var box = Rect2()
        // Kahan summation of the signed area.
        var area = 0.0
        var compensation = 0.0
        let finished = loop(first) { v in
            box.union(polygon[v].pos)
            let area1 = determinant2x2(polygon[v].pos - origin, polygon[polygon[v].right].pos - origin)
            let t1 = area + area1
            compensation += (area - t1) + area1
            area = t1
            if polygon[v].pos.x > maxX, isReflex(v, epsilon) {
                maxX = polygon[v].pos.x
                start = v
            }
        }
        guard finished != nil else {
            return // every ear was degenerate and already clipped
        }
        area += compensation
        let size = box.size
        let minArea = epsilon * max(size.x, size.y)
        if maxX.isFinite, area < -minArea {
            holes.append(start)
            holeBox[start] = box
        } else {
            simples.append(start)
            if area > minArea {
                outers.append(start)
            }
        }
    }

    /// Attaches a hole to an outer contour, checking edges ahead and behind instead of
    /// trusting a sort that ε could break.
    private mutating func cutKeyhole(_ start: Int) {
        let box = holeBox[start]!
        let startPos = polygon[start].pos
        let onTop = startPos.y >= box.max.y - epsilon ? 1 : (startPos.y <= box.min.y + epsilon ? -1 : 0)
        var connector: Int?
        for first in outers {
            loop(first) { edge in
                let x = interpY2X(edge, startPos, onTop: onTop, epsilon)
                guard x.isFinite, insideEdge(start, tail: edge, epsilon, toLeft: true) else {
                    return
                }
                if let current = connector {
                    let currentPos = polygon[current].pos
                    let better = ccw(SIMD2(x, startPos.y), currentPos, polygon[polygon[current].right].pos, epsilon) == 1 ||
                        (currentPos.y < polygon[edge].pos.y
                            ? insideEdge(edge, tail: current, epsilon, toLeft: false)
                            : !insideEdge(current, tail: edge, epsilon, toLeft: false))
                    if better {
                        connector = edge
                    }
                } else {
                    connector = edge
                }
            }
        }
        guard let edge = connector else {
            // The hole found no outer contour; triangulate it on its own.
            simples.append(start)
            return
        }
        joinPolygons(start, findCloserBridge(start, edge))
    }

    /// Refines the keyhole connection to the closest reflex vert in the bridging triangle.
    private func findCloserBridge(_ start: Int, _ edge: Int) -> Int {
        let startPos = polygon[start].pos
        let edgePos = polygon[edge].pos
        let edgeRight = polygon[edge].right
        let edgeRightPos = polygon[edgeRight].pos
        var connector = edgePos.x < startPos.x ? edgeRight
            : edgeRightPos.x < startPos.x ? edge
            : edgeRightPos.y - startPos.y > startPos.y - edgePos.y ? edge : edgeRight
        if abs(polygon[connector].pos.y - startPos.y) <= epsilon {
            return connector
        }
        let above: Double = polygon[connector].pos.y > startPos.y ? 1 : -1
        for first in outers {
            loop(first) { vert in
                let vertPos = polygon[vert].pos
                let connectorPos = polygon[connector].pos
                let inside = above * Double(ccw(startPos, vertPos, connectorPos, epsilon))
                if vertPos.x > startPos.x - epsilon, vertPos.y * above > startPos.y * above - epsilon,
                   inside > 0 || (inside == 0 && vertPos.x < connectorPos.x && vertPos.y * above < connectorPos.y * above),
                   insideEdge(vert, tail: edge, epsilon, toLeft: true), isReflex(vert, epsilon) {
                    connector = vert
                }
            }
        }
        return connector
    }

    /// Duplicates the hole start and connector and splices them into one contour.
    private mutating func joinPolygons(_ start: Int, _ connector: Int) {
        polygon.append(polygon[start])
        let newStart = polygon.count - 1
        polygon.append(polygon[connector])
        let newConnector = polygon.count - 1
        polygon[newStart].inQueue = false
        polygon[newConnector].inQueue = false

        polygon[polygon[start].right].left = newStart
        polygon[polygon[connector].left].right = newConnector
        link(start, connector)
        link(newConnector, newStart)

        clipIfDegenerate(start)
        clipIfDegenerate(newStart)
        clipIfDegenerate(connector)
        clipIfDegenerate(newConnector)
    }

    // MARK: Ear queue

    private mutating func enqueue(_ v: Int) {
        polygon[v].earVersion += 1
        polygon[v].inQueue = true
        sequence += 1
        let entry = QueueEntry(cost: polygon[v].cost, sequence: sequence, vert: v, version: polygon[v].earVersion)
        heap.append(entry)
        var child = heap.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard Self.less(heap[child], heap[parent]) else {
                break
            }
            heap.swapAt(child, parent)
            child = parent
        }
    }

    private mutating func dequeue(_ v: Int) {
        // Lazy removal: invalidate the vertex's current entry.
        polygon[v].earVersion += 1
        polygon[v].inQueue = false
    }

    private mutating func popBest() -> Int? {
        while !heap.isEmpty {
            let top = heap[0]
            let last = heap.removeLast()
            if !heap.isEmpty {
                heap[0] = last
                var parent = 0
                while true {
                    let left = 2 * parent + 1
                    let right = left + 1
                    var smallest = parent
                    if left < heap.count, Self.less(heap[left], heap[smallest]) {
                        smallest = left
                    }
                    if right < heap.count, Self.less(heap[right], heap[smallest]) {
                        smallest = right
                    }
                    if smallest == parent {
                        break
                    }
                    heap.swapAt(parent, smallest)
                    parent = smallest
                }
            }
            if polygon[top.vert].inQueue, polygon[top.vert].earVersion == top.version {
                polygon[top.vert].inQueue = false
                return top.vert
            }
        }
        return nil
    }

    /// Multiset order: lower cost first, then insertion order.
    private static func less(_ a: QueueEntry, _ b: QueueEntry) -> Bool {
        a.cost != b.cost ? a.cost < b.cost : a.sequence < b.sequence
    }

    private mutating func processEar(_ v: Int) {
        if polygon[v].inQueue {
            dequeue(v)
        }
        if isShort(v, epsilon) {
            polygon[v].cost = Self.best
            enqueue(v)
        } else if isConvexVert(v, 2 * epsilon) {
            polygon[v].cost = earCost(v, epsilon)
            enqueue(v)
        } else {
            polygon[v].cost = 1 // reflex; not queued
        }
    }

    private mutating func buildVertCollider(_ start: Int) {
        var points: [PolyVert] = []
        var verts: [Int] = []
        loop(start) { v in
            points.append(PolyVert(pos: polygon[v].pos, idx: verts.count))
            verts.append(v)
        }
        buildTwoDTree(&points)
        colliderPoints = points
        colliderVerts = verts
    }

    /// The main ear-clipping loop for one simple polygon (holes already keyholed).
    private mutating func triangulatePoly(_ start: Int) {
        buildVertCollider(start)
        guard !colliderVerts.isEmpty else {
            return
        }
        heap.removeAll(keepingCapacity: true)
        for v in polygon.indices {
            polygon[v].inQueue = false
        }
        // A simple polygon always yields two fewer triangles than it has verts.
        var triangleCount = -2
        var queued: [Int] = []
        guard var v = loop(start, { queued.append($0) }) else {
            return
        }
        for vert in queued {
            processEar(vert)
            triangleCount += 1
        }
        while triangleCount > 0 {
            // With no valid ear (geometrically invalid input), clip the backup vert to stay manifold.
            if let ear = popBest() {
                v = ear
            }
            clipEar(v)
            triangleCount -= 1
            processEar(polygon[v].left)
            processEar(polygon[v].right)
            v = polygon[v].right
        }
    }
}
