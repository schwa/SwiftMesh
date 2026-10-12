import simd
@testable import SwiftMesh
import Testing

@Suite("CSG fuzz")
struct CSGFuzzTests {
    private static let shapes: [(String, Mesh)] = [
        ("cube", .cube()), ("icoSphere", .icoSphere(subdivisions: 2)), ("sphere", .sphere(latitudeSegments: 10, longitudeSegments: 16)),
        ("torus", .torus(majorSegments: 16, minorSegments: 8)), ("cylinder", .cylinder(segments: 16)), ("capsule", .capsule(segments: 12))
    ]

    /// Signed volume of a triangulated closed mesh.
    private func volume(_ mesh: Mesh) -> Double {
        let triangles = mesh.triangulated()
        return triangles.topology.faces.reduce(0) { total, face in
            let v = triangles.topology.vertexLoop(for: face.id).map { SIMD3<Double>(triangles.positions[$0.raw]) }
            return total + simd_dot(v[0], simd_cross(v[1], v[2])) / 6
        }
    }

    @Test("Random primitive pairs: every result is a closed, consistent manifold with consistent volumes", arguments: 0..<6)
    func randomPairs(seed: Int) {
        var state = UInt64(seed + 1) &* 0x9E37_79B9_7F4A_7C15
        func next() -> Float {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(state >> 40) / Float(1 << 24)
        }
        func randomTransform(_ mesh: Mesh) -> Mesh {
            let axis = simd_normalize(SIMD3(next() - 0.5, next() - 0.5, next() - 0.5) + [0.013, 0.007, 0])
            let rotation = simd_float4x4(simd_quatf(angle: next() * 6.283, axis: axis))
            let scale = 0.6 + next() * 0.6
            let offset = SIMD3(next() - 0.5, next() - 0.5, next() - 0.5) * 0.7
            return mesh.scaled(by: scale).transformed(by: rotation).translated(by: offset)
        }
        for _ in 0..<5 {
            let (nameA, shapeA) = Self.shapes[Int(next() * Float(Self.shapes.count)) % Self.shapes.count]
            let (nameB, shapeB) = Self.shapes[Int(next() * Float(Self.shapes.count)) % Self.shapes.count]
            let a = randomTransform(shapeA)
            let b = randomTransform(shapeB)
            let label = "\(nameA) vs \(nameB), seed \(seed)"
            var volumes: [CSGOperation: Double] = [:]
            for operation in [CSGOperation.union, .intersection, .difference] {
                let result = a.csg(operation, b)
                volumes[operation] = volume(result)
                guard result.faceCount > 0 else {
                    continue
                }
                #expect(result.validate().isEmpty, "\(operation) \(label)")
                #expect(result.isManifold, "\(operation) \(label)")
                #expect(result.topology.boundaryLoopCount == 0, "\(operation) \(label)")
                #expect(!result.topology.hasInconsistentFaceWinding, "\(operation) \(label)")
            }
            // Inclusion-exclusion on volume, up to the welding/merging of nearly-coincident geometry.
            let volumeA = volume(a)
            let volumeB = volume(b)
            let tolerance = 1e-3 * max(volumeA, volumeB)
            #expect(abs(volumes[.union]! + volumes[.intersection]! - volumeA - volumeB) < tolerance, "\(label)")
            #expect(abs(volumes[.difference]! + volumes[.intersection]! - volumeA) < tolerance, "\(label)")
        }
    }

    @Test("Touching, coincident, and self cases")
    func degenerateCases() {
        let cube = Mesh.cube()
        #expect(cube.difference(cube).faceCount == 0)
        #expect(abs(volume(cube.intersection(cube)) - 1) < 1e-6)
        let touching = cube.union(cube.translated(by: [1, 0, 0]))
        #expect(touching.isManifold)
        #expect(touching.topology.surfaceComponents().count == 1)
        #expect(abs(volume(touching) - 2) < 1e-6)
        let shared = cube.union(cube.translated(by: [0.5, 0.5, 0]))
        #expect(shared.isManifold)
        #expect(abs(volume(shared) - 1.75) < 1e-6)
    }

    @Test("Coplanar merge keeps holes: cube minus a protruding sphere stays manifold")
    func mergeKeepsHoles() {
        let cube = Mesh.box(extents: [0.5, 0.5, 0.5], attributes: []).translated(by: [0.2, 0.2, 0.2])
        let sphere = Mesh.icoSphere(extents: [0.45, 0.45, 0.45], subdivisions: 2, attributes: [])
        let merged = cube.difference(sphere)
        let raw = cube.difference(sphere, mergeCoplanar: false)
        #expect(merged.isManifold)
        #expect(merged.topology.boundaryLoopCount == 0)
        #expect(merged.validate().isEmpty)
        #expect(merged.faceCount < raw.faceCount)
        #expect(abs(volume(merged) - volume(raw)) < 1e-6)
    }

    @Test("Chained differences with merged coplanar faces stay manifold and non-empty")
    func chainedDifferences() {
        let t: Float = 0.02
        let wall = Mesh.box(extents: [0.8, 0.5, t], attributes: [])
        let door = Mesh.box(extents: [0.18, 0.3, t * 2], attributes: []).translated(by: [0.1, -0.1, 0])
        let window1 = Mesh.box(extents: [0.12, 0.12, t * 2], attributes: []).translated(by: [-0.25, 0.06, 0])
        let window2 = Mesh.box(extents: [0.12, 0.12, t * 2], attributes: []).translated(by: [0.3, 0.06, 0])
        var result = wall
        for cutter in [door, window1, window2] {
            result = result.difference(cutter)
            #expect(result.isManifold)
            #expect(result.faceCount > 0)
        }
        // Merged front and back faces each have two window holes (the door opens the bottom edge).
        #expect(result.topology.faces.filter { $0.holeEdges.count == 2 }.count == 2)
        // The door spans y -0.25...0.05, flush with the wall's bottom edge (a notch, not a hole).
        let expected = (0.8 * 0.5 - 0.18 * 0.3 - 2 * 0.12 * 0.12) * Double(t)
        #expect(abs(volume(result) - expected) < 1e-6)
    }

    @Test("Non-manifold input gives an empty result")
    func nonManifoldInput() {
        #expect(Mesh.quad().union(Mesh.cube()).faceCount == 0)
    }
}
