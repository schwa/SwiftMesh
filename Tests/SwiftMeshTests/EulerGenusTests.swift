import simd
@testable import SwiftMesh
import SwiftUI
import Testing

@Suite("Euler characteristic and genus")
struct EulerGenusTests {
    @Test("Sphere-like closed meshes have chi 2 and genus 0")
    func sphere() {
        for mesh in [Mesh.icoSphere(subdivisions: 2, attributes: []), .cube(attributes: []), .tetrahedron(attributes: [])] {
            let components = mesh.topology.surfaceComponents()
            #expect(components.count == 1)
            #expect(components[0].eulerCharacteristic == 2)
            #expect(components[0].boundaryLoopCount == 0)
            #expect(components[0].isOrientable)
            #expect(components[0].genus == 0)
        }
    }

    @Test("Torus has chi 0 and genus 1")
    func torus() {
        let component = Mesh.torus(attributes: []).topology.surfaceComponents()[0]
        #expect(component.eulerCharacteristic == 0)
        #expect(component.genus == 1)
    }

    @Test("Faces with holes count correctly: extruded square ring is genus 1")
    func holedFaces() {
        var path = Path(CGRect(x: 0, y: 0, width: 4, height: 4))
        path.addPath(Path(CGRect(x: 1, y: 1, width: 2, height: 2)))
        let mesh = Mesh.extruded(path, depth: 1, attributes: [])
        #expect(mesh.topology.eulerCharacteristic == 0)
        #expect(mesh.topology.surfaceComponents()[0].genus == 1)
    }

    @Test("Open disc has one boundary loop and genus 0")
    func disc() {
        let component = Mesh.circle(attributes: []).topology.surfaceComponents()[0]
        #expect(component.eulerCharacteristic == 1)
        #expect(component.boundaryLoopCount == 1)
        #expect(component.genus == 0)
    }

    @Test("Disconnected meshes are reported per component")
    func disconnected() {
        let mesh = Mesh.merged([Mesh.icoSphere(subdivisions: 1, attributes: []), Mesh.torus(attributes: []).translated(by: [5, 0, 0])])
        let components = mesh.topology.surfaceComponents()
        #expect(components.count == 2)
        #expect(components.map(\.genus) == [0, 1])
        #expect(mesh.topology.eulerCharacteristic == 2)
        #expect(mesh.topology.hasConsistentGenus)
    }

    @Test("Möbius strip is non-orientable")
    func mobius() {
        // A strip of quads whose last quad reconnects with a half twist.
        let segments = 8
        var positions: [SIMD3<Float>] = []
        for index in 0..<segments {
            let angle = Float(index) / Float(segments) * 2 * .pi
            let twist = angle / 2
            let center = SIMD3<Float>(cos(angle), sin(angle), 0)
            let offset = SIMD3<Float>(cos(angle) * cos(twist), sin(angle) * cos(twist), sin(twist)) * 0.3
            positions += [center - offset, center + offset]
        }
        var faces: [[Int]] = []
        for index in 0..<(segments - 1) {
            faces.append([2 * index, 2 * index + 2, 2 * index + 3, 2 * index + 1])
        }
        // Closing quad swaps sides: that's the half twist.
        let last = 2 * (segments - 1)
        faces.append([last, 1, 0, last + 1])
        let mesh = Mesh(positions: positions, faces: faces)
        let components = mesh.topology.surfaceComponents()
        #expect(components.contains { !$0.isOrientable })
    }
}
