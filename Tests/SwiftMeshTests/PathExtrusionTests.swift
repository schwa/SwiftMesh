import simd
@testable import SwiftMesh
import SwiftUI
import Testing

@Suite("Path extrusion")
struct PathExtrusionTests {
    @Test("Rectangle extrudes to a closed box with outward faces")
    func rectangle() {
        let mesh = Mesh.extruded(Path(CGRect(x: 0, y: 0, width: 2, height: 1)), depth: 0.5, attributes: [])
        #expect(mesh.faceCount == 6)
        #expect(mesh.validate().isEmpty)
        #expect(mesh.isManifold)
        #expect(mesh.bounds.min == [0, -1, 0])
        #expect(mesh.bounds.max == [2, 0, 0.5])
        let center = mesh.center
        for face in mesh.topology.faces {
            #expect(simd_dot(mesh.faceNormal(face.id), mesh.faceCentroid(face.id) - center) > 0)
        }
    }

    @Test("Nested subpath becomes a hole regardless of its winding", arguments: [false, true])
    func hole(reverseInner: Bool) {
        var path = Path(CGRect(x: 0, y: 0, width: 4, height: 4))
        var inner = Path(CGRect(x: 1, y: 1, width: 2, height: 2))
        if reverseInner {
            inner = Path { $0.addLines([CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 3), CGPoint(x: 3, y: 3), CGPoint(x: 3, y: 1)]); $0.closeSubpath() }
        }
        path.addPath(inner)
        let mesh = Mesh.extruded(path, depth: 1, attributes: [])
        #expect(mesh.validate().isEmpty)
        #expect(mesh.isManifold)
        #expect(mesh.topology.faces.filter { !$0.holeEdges.isEmpty }.count == 2)
        let holeRings = mesh.topology.faces.reduce(0) { $0 + $1.holeEdges.count }
        #expect(mesh.vertexCount - mesh.edgeCount + mesh.faceCount - holeRings == 0) // genus 1
    }

    @Test("Walls only: no caps, one open band per outline")
    func wallsOnly() {
        var path = Path(CGRect(x: 0, y: 0, width: 4, height: 4))
        path.addPath(Path(CGRect(x: 1, y: 1, width: 2, height: 2)))
        let mesh = Mesh.extruded(path, depth: 1, mode: .wallsOnly, attributes: [])
        #expect(mesh.faceCount == 8)
        #expect(mesh.validate().isEmpty)
        #expect(mesh.topology.boundaryLoopCount == 4) // top and bottom rim of each band
        #expect(mesh.topology.faces.allSatisfy { abs(mesh.faceNormal($0.id).z) < 1e-6 })
    }

    @Test("Thin walls on a rectangle: closed genus-1 ring with the expected inner size")
    func thinWalls() {
        let mesh = Mesh.extruded(Path(CGRect(x: 0, y: 0, width: 4, height: 2)), depth: 1, mode: .thinWalls(thickness: 0.5), attributes: [])
        #expect(mesh.validate().isEmpty)
        #expect(mesh.isManifold)
        #expect(!mesh.topology.hasInconsistentFaceWinding)
        #expect(mesh.topology.surfaceComponents().map(\.genus) == [1])
        // Inner vertices form a 3 x 1 rectangle inset by 0.5 (y is flipped: 0...-2).
        let inner = mesh.positions.filter { $0.x > 0.01 && $0.x < 3.99 }
        #expect(Set(inner.map { [$0.x, $0.y] }) == [[0.5, -0.5], [3.5, -0.5], [3.5, -1.5], [0.5, -1.5]])
        // Faces point away from the wall material.
        let center = SIMD3<Float>(2, -1, 0.5)
        let outward = mesh.topology.faces.filter { face in
            let normal = mesh.faceNormal(face.id)
            let centroid = mesh.faceCentroid(face.id)
            if abs(normal.z) > 0.99 { return true } // caps
            let isOuterWall = centroid.x < 0.01 || centroid.x > 3.99 || centroid.y > -0.01 || centroid.y < -1.99
            let away = simd_dot(normal, centroid - center)
            return isOuterWall ? away > 0 : away < 0
        }
        #expect(outward.count == mesh.faceCount)
    }

    @Test("Thin walls keep holes: a frame becomes two concentric rings")
    func thinWallsWithHole() {
        var path = Path(CGRect(x: 0, y: 0, width: 4, height: 4))
        path.addPath(Path(CGRect(x: 1, y: 1, width: 2, height: 2)))
        let mesh = Mesh.extruded(path, depth: 1, mode: .thinWalls(thickness: 0.2), attributes: [])
        #expect(mesh.isManifold)
        #expect(mesh.topology.surfaceComponents().map(\.genus) == [1, 1])
        // The hole's wall grows outward into the material: its outer edge is at 0.8 and 3.2.
        #expect(mesh.positions.contains { abs($0.x - 0.8) < 1e-5 && abs($0.y + 0.8) < 1e-5 })
    }

    @Test("Curved path with attributes stays closed and triangulates")
    func circle() {
        let mesh = Mesh.extruded(Path(ellipseIn: CGRect(x: 0, y: 0, width: 2, height: 2)), depth: 1, curveSegments: 6)
        #expect(mesh.isManifold)
        #expect(mesh.validate().isEmpty)
        #expect(mesh.triangulated().isManifold)
    }
}
