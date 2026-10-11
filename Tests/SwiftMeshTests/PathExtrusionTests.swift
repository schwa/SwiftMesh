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

    @Test("Curved path with attributes stays closed and triangulates")
    func circle() {
        let mesh = Mesh.extruded(Path(ellipseIn: CGRect(x: 0, y: 0, width: 2, height: 2)), depth: 1, curveSegments: 6)
        #expect(mesh.isManifold)
        #expect(mesh.validate().isEmpty)
        #expect(mesh.triangulated().isManifold)
    }
}
