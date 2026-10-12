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
    /// The offset uses miter joins and does not resolve self-intersections at sharp concave
    /// corners or where `thickness` exceeds the local feature size.
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

private extension Mesh {
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

    /// Offset a closed loop toward its left side with miter joins.
    static func offsetLeft(_ loop: [SIMD2<Float>], by distance: Float) -> [SIMD2<Float>] {
        func leftNormal(_ from: SIMD2<Float>, _ to: SIMD2<Float>) -> SIMD2<Float> {
            let direction = simd_normalize(to - from)
            return SIMD2(-direction.y, direction.x)
        }
        return loop.indices.map { index in
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
