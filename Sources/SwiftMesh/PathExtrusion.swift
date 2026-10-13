import CoreGraphics
import simd
import SwiftUI

/// What ``Mesh/extruded(_:depth:mode:curveSegments:attributes:)-(CGPath,_,_,_,_)`` builds from each outline.
public enum ExtrusionMode: Sendable, Equatable {
    /// Front and back caps joined by side walls: a closed solid.
    case solid
    /// Side walls only, no caps: an open band per outline (fences, walls from a floor plan).
    case wallsOnly
    /// Each outline becomes a closed wall `thickness` thick, offset toward the shape's material.
    ///
    /// Simple shapes get a direct miter offset. When that offset would fold or cross (sharp
    /// corners, notches, features thinner than twice `thickness`), the wall is built with CSG
    /// instead: the solid intersected with a band along every edge, with mitered joins limited
    /// to twice `thickness` and rounded beyond. That path is slower and returns triangles.
    case thinWalls(thickness: Float)
}

public extension Mesh {
    /// Extrude a SwiftUI path. See ``extruded(_:depth:mode:curveSegments:attributes:)-(CGPath,_,_,_,_)``.
    static func extruded(_ path: Path, depth: Float, mode: ExtrusionMode = .solid, curveSegments: Int = 8, attributes: MeshAttributes = .default) -> Mesh {
        extruded(path.cgPath, depth: depth, mode: mode, curveSegments: curveSegments, attributes: attributes)
    }

    /// Extrude a path into a closed solid.
    ///
    /// Each closed subpath is flattened (curves become `curveSegments` line segments).
    /// Subpaths nested inside an odd number of others become holes, as with the
    /// even-odd fill rule. The back cap lies at z = 0 and the front cap at z = `depth`,
    /// joined by quad side walls. Path y is flipped so the shape reads the same as on
    /// screen when viewed from +z. Caps are n-gon faces with holes. `mode` selects solid,
    /// walls-only, or thin-wall output (see ``ExtrusionMode``).
    static func extruded(_ path: CGPath, depth: Float, mode: ExtrusionMode = .solid, curveSegments: Int = 8, attributes: MeshAttributes = .default) -> Mesh {
        let loops = flattenedLoops(path, curveSegments: curveSegments)
        guard !loops.isEmpty else {
            return Mesh(positions: [], faces: [[Int]]())
        }

        let containers = loops.indices.map { index in
            loops.indices.filter { $0 != index && contains(loops[$0], loops[index][0]) }
        }
        // Outer loops counter-clockwise, holes clockwise (viewed from +z).
        let oriented = loops.indices.map { index in
            let isHole = !containers[index].count.isMultiple(of: 2)
            return (signedArea(loops[index]) > 0) == isHole ? Array(loops[index].reversed()) : loops[index]
        }

        var positions: [SIMD3<Float>] = []
        var back: [[Int]] = []
        var front: [[Int]] = []
        for loop in oriented {
            back.append(loop.indices.map { positions.count + $0 })
            positions += loop.map { SIMD3($0.x, $0.y, 0) }
            front.append(loop.indices.map { positions.count + $0 })
            positions += loop.map { SIMD3($0.x, $0.y, depth) }
        }

        if case .thinWalls(let thickness) = mode, !miterOffsetIsSafe(oriented, thickness: thickness) {
            let solid = extruded(path, depth: depth, mode: .solid, curveSegments: curveSegments, attributes: [])
            var mesh = robustThinWalls(oriented, solid: solid, depth: depth, thickness: thickness)
            mesh.applyAttributes(attributes)
            return mesh
        }

        var faces: [HalfEdgeTopology.FaceDefinition] = []
        if case .thinWalls(let thickness) = mode {
            // Material lies to the left of every oriented loop (outer CCW, holes CW).
            for index in oriented.indices {
                let inner = offsetLeft(oriented[index], by: thickness)
                let innerBack = inner.indices.map { positions.count + $0 }
                positions += inner.map { SIMD3($0.x, $0.y, 0) }
                let innerFront = inner.indices.map { positions.count + $0 }
                positions += inner.map { SIMD3($0.x, $0.y, depth) }
                let count = inner.count
                for corner in 0..<count {
                    let next = (corner + 1) % count
                    faces.append(.init(outer: [front[index][corner], front[index][next], innerFront[next], innerFront[corner]]))
                    faces.append(.init(outer: [back[index][corner], innerBack[corner], innerBack[next], back[index][next]]))
                    faces.append(.init(outer: [innerBack[next], innerBack[corner], innerFront[corner], innerFront[next]]))
                }
            }
        }
        for index in loops.indices where mode == .solid && containers[index].count.isMultiple(of: 2) {
            let holes = loops.indices.filter { containers[$0].count == containers[index].count + 1 && containers[$0].contains(index) }
            faces.append(.init(outer: front[index], holes: holes.map { front[$0] }))
            faces.append(.init(outer: back[index].reversed(), holes: holes.map { back[$0].reversed() }))
        }
        // Wall (a, b, b', a') for front edge a' → b': twins the back cap's b → a and the front cap's a' → b'.
        for index in loops.indices {
            let count = loops[index].count
            for corner in 0..<count {
                let next = (corner + 1) % count
                faces.append(.init(outer: [back[index][corner], back[index][next], front[index][next], front[index][corner]]))
            }
        }

        var mesh = Mesh(positions: positions, faces: faces)
        mesh.applyAttributes(attributes)
        return mesh
    }
}

extension Mesh {
    static func flattenedLoops(_ path: CGPath, curveSegments: Int) -> [[SIMD2<Float>]] {
        var loops: [[SIMD2<Float>]] = []
        var current: [SIMD2<Float>] = []
        func point(_ cgPoint: CGPoint) -> SIMD2<Float> {
            SIMD2(Float(cgPoint.x), -Float(cgPoint.y))
        }
        func finish() {
            if let first = current.first, let last = current.last, current.count > 1, simd_distance(first, last) < 1e-6 {
                current.removeLast()
            }
            // Drop consecutive duplicates.
            current = current.enumerated().compactMap { index, value in
                index > 0 && simd_distance(value, current[index - 1]) < 1e-6 ? nil : value
            }
            if current.count >= 3, abs(signedArea(current)) > 1e-9 {
                loops.append(current)
            }
            current = []
        }
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let points = element.points
            switch element.type {
            case .moveToPoint:
                finish()
                current = [point(points[0])]

            case .addLineToPoint:
                current.append(point(points[0]))

            case .addQuadCurveToPoint:
                let start = current.last ?? point(points[0])
                let control = point(points[0])
                let end = point(points[1])
                for step in 1...curveSegments {
                    let t = Float(step) / Float(curveSegments)
                    let u = 1 - t
                    current.append(u * u * start + 2 * u * t * control + t * t * end)
                }

            case .addCurveToPoint:
                let start = current.last ?? point(points[0])
                let control1 = point(points[0])
                let control2 = point(points[1])
                let end = point(points[2])
                for step in 1...curveSegments {
                    let t = Float(step) / Float(curveSegments)
                    let u = 1 - t
                    current.append(u * u * u * start + 3 * u * u * t * control1 + 3 * u * t * t * control2 + t * t * t * end)
                }

            case .closeSubpath:
                finish()

            @unknown default:
                break
            }
        }
        finish()
        return loops
    }

    static func leftNormal(_ from: SIMD2<Float>, _ to: SIMD2<Float>) -> SIMD2<Float> {
        let direction = simd_normalize(to - from)
        return SIMD2(-direction.y, direction.x)
    }

    /// Whether the miter offset of every loop stays simple: no sharp corners, no crossing
    /// edges (within or between loops, original or offset), and no inverted offset loop.
    static func miterOffsetIsSafe(_ loops: [[SIMD2<Float>]], thickness: Float) -> Bool {
        var segments: [(a: SIMD2<Float>, b: SIMD2<Float>, loop: Int, index: Int, count: Int)] = []
        for (loopIndex, loop) in loops.enumerated() {
            for index in loop.indices {
                let incoming = leftNormal(loop[(index + loop.count - 1) % loop.count], loop[index])
                let outgoing = leftNormal(loop[index], loop[(index + 1) % loop.count])
                // Corners sharper than 60 degrees push the miter more than 2x thickness out.
                if 1 + simd_dot(incoming, outgoing) < 0.5 {
                    return false
                }
            }
            let inner = offsetLeft(loop, by: thickness)
            if (signedArea(inner) > 0) != (signedArea(loop) > 0) {
                return false
            }
            for (offset, points) in [(0, loop), (loops.count, inner)] {
                for index in points.indices {
                    segments.append((points[index], points[(index + 1) % points.count], loopIndex + offset, index, points.count))
                }
            }
        }
        func orientation(_ p: SIMD2<Float>, _ q: SIMD2<Float>, _ r: SIMD2<Float>) -> Float {
            (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
        }
        for first in segments.indices {
            let s = segments[first]
            for second in (first + 1)..<segments.count {
                let t = segments[second]
                if s.loop == t.loop {
                    let gap = abs(s.index - t.index)
                    if gap == 1 || gap == s.count - 1 {
                        continue
                    }
                }
                guard max(s.a.x, s.b.x) >= min(t.a.x, t.b.x), max(t.a.x, t.b.x) >= min(s.a.x, s.b.x),
                      max(s.a.y, s.b.y) >= min(t.a.y, t.b.y), max(t.a.y, t.b.y) >= min(s.a.y, s.b.y) else {
                    continue
                }
                // Touching counts as crossing: the fast path stays conservative.
                if orientation(s.a, s.b, t.a) * orientation(s.a, s.b, t.b) <= 0,
                   orientation(t.a, t.b, s.a) * orientation(t.a, t.b, s.b) <= 0 {
                    return false
                }
            }
        }
        return true
    }

    /// Thin walls via CSG: the solid intersected with the union of a `thickness`-wide band
    /// on the material side of every edge, plus a join wedge where consecutive bands diverge.
    static func robustThinWalls(_ loops: [[SIMD2<Float>]], solid: Mesh, depth: Float, thickness: Float) -> Mesh {
        // Bands overshoot the caps so the intersection cuts them cleanly.
        let margin = max(depth, thickness)
        var pieces: [Mesh] = []
        for loop in loops {
            let count = loop.count
            for index in 0..<count {
                let a = loop[index]
                let b = loop[(index + 1) % count]
                let c = loop[(index + 2) % count]
                guard simd_distance(a, b) > 1e-7 else {
                    continue
                }
                let normal = leftNormal(a, b)
                pieces.append(prism([a, b, b + normal * thickness, a + normal * thickness], from: -margin, to: depth + margin))
                guard simd_distance(b, c) > 1e-7 else {
                    continue
                }
                // A right turn opens a gap between this band and the next on the material side.
                let incoming = simd_normalize(b - a)
                let outgoing = simd_normalize(c - b)
                guard incoming.x * outgoing.y - incoming.y * outgoing.x < -1e-6 else {
                    continue
                }
                let nextNormal = leftNormal(b, c)
                let denominator = 1 + simd_dot(normal, nextNormal)
                var wedge = [b, b + normal * thickness]
                if denominator >= 0.5 {
                    wedge.append(b + (normal + nextNormal) * (thickness / denominator))
                } else {
                    // Too sharp to miter: a round join, in steps of at most 22.5 degrees.
                    let start = atan2(normal.y, normal.x)
                    // Right turn: the normal rotates clockwise, so sweep negative.
                    var sweep = atan2(nextNormal.y, nextNormal.x) - start
                    sweep = sweep > 0 ? sweep - 2 * .pi : sweep
                    let steps = Int((abs(sweep) / (.pi / 8)).rounded(.up))
                    for step in 1..<max(steps, 1) {
                        let angle = start + sweep * Float(step) / Float(steps)
                        wedge.append(b + SIMD2(cos(angle), sin(angle)) * thickness)
                    }
                }
                wedge.append(b + nextNormal * thickness)
                pieces.append(prism(wedge, from: -margin, to: depth + margin))
            }
        }
        // Balanced union keeps intermediate meshes small.
        while pieces.count > 1 {
            pieces = stride(from: 0, to: pieces.count, by: 2).map { index in
                index + 1 < pieces.count ? pieces[index].union(pieces[index + 1], mergeCoplanar: false) : pieces[index]
            }
        }
        guard let bands = pieces.first else {
            return Mesh(positions: [], faces: [[Int]]())
        }
        return solid.intersection(bands)
    }

    /// A closed prism over a convex polygon, z from `bottom` to `top`.
    static func prism(_ polygon: [SIMD2<Float>], from bottom: Float, to top: Float) -> Mesh {
        let polygon = signedArea(polygon) < 0 ? Array(polygon.reversed()) : polygon
        let count = polygon.count
        let positions = polygon.map { SIMD3($0.x, $0.y, bottom) } + polygon.map { SIMD3($0.x, $0.y, top) }
        var faces: [[Int]] = [Array((0..<count).reversed()), Array(count..<(2 * count))]
        for index in 0..<count {
            let next = (index + 1) % count
            faces.append([index, next, count + next, count + index])
        }
        return Mesh(positions: positions, faces: faces)
    }

    /// Offset a closed loop toward its left side with miter joins.
    static func offsetLeft(_ loop: [SIMD2<Float>], by distance: Float) -> [SIMD2<Float>] {
        loop.indices.map { index in
            let previous = loop[(index + loop.count - 1) % loop.count]
            let next = loop[(index + 1) % loop.count]
            let incoming = leftNormal(previous, loop[index])
            let outgoing = leftNormal(loop[index], next)
            // Miter: the point distance from both offset edges; clamp near-reversals.
            let denominator = max(1 + simd_dot(incoming, outgoing), 0.1)
            return loop[index] + (incoming + outgoing) * (distance / denominator)
        }
    }

    static func signedArea(_ loop: [SIMD2<Float>]) -> Float {
        var area: Float = 0
        for index in loop.indices {
            let a = loop[index]
            let b = loop[(index + 1) % loop.count]
            area += a.x * b.y - b.x * a.y
        }
        return area / 2
    }

    static func contains(_ polygon: [SIMD2<Float>], _ test: SIMD2<Float>) -> Bool {
        var inside = false
        var previous = polygon.count - 1
        for index in polygon.indices {
            let a = polygon[index]
            let b = polygon[previous]
            if (a.y > test.y) != (b.y > test.y), test.x < (b.x - a.x) * (test.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            previous = index
        }
        return inside
    }
}
