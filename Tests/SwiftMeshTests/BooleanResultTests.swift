import simd
@testable import SwiftMesh
import Testing

@Suite("Boolean result assembly")
struct BooleanResultTests {
    private func run(_ a: Mesh, _ b: Mesh, _ operation: BooleanOperation) throws -> (BooleanFaces, BooleanMesh) {
        let faces = BooleanAssembler(try BooleanMesh(mesh: a), try BooleanMesh(mesh: b), operation: operation).assemble()
        return (faces, faces.triangulated())
    }

    /// Polygon half-edges pair with their reverse, and every face's edges form closed loops.
    private func checkPolygons(_ faces: BooleanFaces) {
        for (index, edge) in faces.halfedges.enumerated() {
            #expect(edge.pairedHalfedge >= 0)
            guard edge.pairedHalfedge >= 0 else {
                continue
            }
            let pair = faces.halfedges[edge.pairedHalfedge]
            #expect(pair.pairedHalfedge == index)
            #expect(pair.startVert == edge.endVert && pair.endVert == edge.startVert)
        }
        for face in 0..<faces.numFace {
            let loops = faces.assembleLoops(face: face)
            #expect(loops.reduce(0) { $0 + $1.count } == faces.faceEdge[face + 1] - faces.faceEdge[face])
            for loop in loops {
                for (index, edge) in loop.enumerated() {
                    #expect(faces.halfedges[edge].endVert == faces.halfedges[loop[(index + 1) % loop.count]].startVert)
                }
            }
        }
    }

    private func volume(_ mesh: BooleanMesh) -> Double {
        (0..<mesh.numTri).reduce(0) { total, triangle in
            let a = mesh.vertPos[mesh.halfedges[3 * triangle].startVert]
            let b = mesh.vertPos[mesh.halfedges[3 * triangle + 1].startVert]
            let c = mesh.vertPos[mesh.halfedges[3 * triangle + 2].startVert]
            return total + simd_dot(a, simd_cross(b, c)) / 6
        }
    }

    @Test("Overlapping cubes: exact volumes, closed polygons, manifold triangles", arguments: [
        (BooleanOperation.union, 1.5), (.intersection, 0.5), (.difference, 0.5)
    ])
    func cubes(operation: BooleanOperation, expected: Double) throws {
        let (faces, mesh) = try run(.cube(attributes: []), Mesh.cube(attributes: []).translated(by: [0.5, 0, 0]), operation)
        checkPolygons(faces)
        #expect(mesh.isManifold)
        #expect(abs(volume(mesh) - expected) < 1e-12)
    }

    @Test("Generic position: sphere and rotated cube stay closed, volumes add up")
    func sphereCube() throws {
        let sphere = Mesh.icoSphere(extents: [0.8, 0.8, 0.8], subdivisions: 2, attributes: [])
        let rotation = simd_float4x4(simd_quatf(angle: 0.6, axis: simd_normalize([1, 2, 3])))
        let cube = Mesh.cube(extents: [0.5, 0.5, 0.5], attributes: []).transformed(by: rotation).translated(by: [0.2, 0.15, 0.1])
        var volumes: [BooleanOperation: Double] = [:]
        for operation in [BooleanOperation.union, .intersection, .difference] {
            let (faces, mesh) = try run(sphere, cube, operation)
            checkPolygons(faces)
            #expect(mesh.isManifold, "\(operation)")
            #expect(faces.vertPos.count > faces.retainedVertexCount, "new verts were created")
            volumes[operation] = volume(mesh)
        }
        let sphereVolume = volume(try BooleanMesh(mesh: sphere))
        let cubeVolume = volume(try BooleanMesh(mesh: cube))
        // Inclusion-exclusion holds exactly for polyhedra (up to rounding).
        #expect(abs(volumes[.union]! + volumes[.intersection]! - sphereVolume - cubeVolume) < 1e-9)
        #expect(abs(volumes[.difference]! + volumes[.intersection]! - sphereVolume) < 1e-9)
    }

    @Test("A mesh minus itself is empty; intersected with itself is itself")
    func selfOperations() throws {
        let mesh = Mesh.icoSphere(subdivisions: 1, attributes: [])
        let (_, difference) = try run(mesh, mesh, .difference)
        #expect(difference.numTri == 0)
        let (_, intersection) = try run(mesh, mesh, .intersection)
        #expect(intersection.isManifold)
        #expect(abs(volume(intersection) - volume(try BooleanMesh(mesh: mesh))) < 1e-12)
    }

    @Test("Touching cubes union into one closed solid")
    func touching() throws {
        let (faces, mesh) = try run(.cube(attributes: []), Mesh.cube(attributes: []).translated(by: [1, 0, 0]), .union)
        checkPolygons(faces)
        #expect(mesh.isManifold)
        #expect(abs(volume(mesh) - 2) < 1e-12)
    }

    @Test("Disjoint inputs: union keeps both, intersection is empty, difference keeps P")
    func disjoint() throws {
        let a = Mesh.cube(attributes: [])
        let b = Mesh.cube(attributes: []).translated(by: [3, 0, 0])
        #expect(abs(volume(try run(a, b, .union).1) - 2) < 1e-12)
        #expect(try run(a, b, .intersection).1.numTri == 0)
        #expect(abs(volume(try run(a, b, .difference).1) - 1) < 1e-12)
    }

    @Test("Random rotations: every result is a closed manifold")
    func randomRotations() throws {
        var state: UInt64 = 11
        func next() -> Float {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(state >> 40) / Float(1 << 24)
        }
        let sphere = Mesh.icoSphere(extents: [0.9, 0.9, 0.9], subdivisions: 2, attributes: [])
        for _ in 0..<30 {
            let axis = simd_normalize(SIMD3(next() - 0.5, next() - 0.5, next() - 0.5) + [0.01, 0, 0])
            let rotation = simd_float4x4(simd_quatf(angle: next() * 6.28, axis: axis))
            let offset = SIMD3(next() - 0.5, next() - 0.5, next() - 0.5) * 0.6
            let cube = Mesh.cube(extents: [0.6, 0.6, 0.6], attributes: []).transformed(by: rotation).translated(by: offset)
            for operation in [BooleanOperation.union, .intersection, .difference] {
                let (faces, mesh) = try run(sphere, cube, operation)
                checkPolygons(faces)
                #expect(mesh.isManifold, "\(operation) offset \(offset)")
            }
        }
    }

    @Test("Result winding: points inside the result wind +1")
    func resultWinding() throws {
        let (_, union) = try run(.cube(attributes: []), Mesh.cube(attributes: []).translated(by: [0.5, 0.25, 0.1]), .union)
        let winding = union.pointWinding([[0.01, 0.02, 0.03], [0.9, 0.5, 0.4], [2, 0, 0]])
        #expect(winding == [1, 1, 0])
    }
}
