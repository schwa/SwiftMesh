import CoreGraphics
import Foundation
import Geometry
@testable import SwiftMesh
import Testing

@Suite("Mesh2D")
struct Mesh2DTests {
    @Test("Triangle mesh from segments")
    func triangleFromSegments() {
        let segments: [Identified<String, LineSegment>] = [
            Identified(id: "AB", value: LineSegment([0, 0], [1, 0])),
            Identified(id: "BC", value: LineSegment([1, 0], [0.5, 1])),
            Identified(id: "CA", value: LineSegment([0.5, 1], [0, 0]))
        ]

        let mesh = Mesh2D(segments: segments)

        #expect(mesh.topology.validate().isEmpty, "Topology should validate")
        #expect(mesh.topology.vertices.count == 3, "Triangle should have 3 vertices")
        #expect(mesh.topology.halfEdges.count == 6, "Triangle should have 6 half-edges")
        #expect(mesh.topology.faces.count == 2, "Triangle should have 2 faces (interior + exterior)")

        for vertex in mesh.topology.vertices {
            #expect(vertex.edge != nil, "Vertex \(vertex.id) should have an outgoing edge")
        }
        for edge in mesh.topology.halfEdges {
            #expect(edge.twin != nil, "Edge \(edge.id) should have a twin")
            #expect(edge.face != nil, "Edge \(edge.id) should belong to a face")
        }
    }

    @Test("Diamond with diagonal — counts, signed areas, orientation")
    func diamondWithDiagonal() {
        let segments: [Identified<String, LineSegment>] = [
            Identified(id: "NE", value: LineSegment([0, 1], [1, 0])),
            Identified(id: "ES", value: LineSegment([1, 0], [0, -1])),
            Identified(id: "SW", value: LineSegment([0, -1], [-1, 0])),
            Identified(id: "WN", value: LineSegment([-1, 0], [0, 1])),
            Identified(id: "NS", value: LineSegment([0, 1], [0, -1]))
        ]

        let mesh = Mesh2D(segments: segments)

        #expect(mesh.topology.validate().isEmpty)
        #expect(mesh.topology.vertices.count == 4)
        #expect(mesh.topology.halfEdges.count == 10)
        #expect(mesh.topology.faces.count == 3)

        let interior = mesh.topology.faces.filter { (mesh.signedArea($0.id) ?? 0) < 0 }
        let exterior = mesh.topology.faces.filter { (mesh.signedArea($0.id) ?? 0) > 0 }

        #expect(interior.count == 2, "Two interior faces (CW)")
        #expect(exterior.count == 1, "One exterior face (CCW)")

        for face in interior {
            let area = mesh.signedArea(face.id) ?? 0
            #expect(abs(abs(area) - 1.0) < 0.01, "Interior triangle should have area ≈ 1")
        }
    }

    @Test("Indexed triangle from points + face definitions")
    func indexedTriangleFromPoints() {
        let points: [CGPoint] = [[0, 0], [1, 0], [0.5, 1]]
        let faces = [HalfEdgeTopology.FaceDefinition(outer: [0, 1, 2])]

        let mesh = Mesh2D(points: points, faces: faces)

        #expect(mesh.topology.vertices.count == 3)
        #expect(mesh.topology.halfEdges.count == 3)
        #expect(mesh.topology.faces.count == 1)

        // Edge labels should be 0, 1, 2 (one per undirected edge).
        #expect(Set(mesh.edgeLabels) == Set([0, 1, 2]))

        let area = mesh.signedArea(HalfEdgeTopology.FaceID(raw: 0)) ?? 0
        #expect(abs(area - 0.5) < 0.01, "CCW triangle should have signed area ≈ +0.5")
    }

    @Test("polygon(for:) recovers the boundary")
    func polygonRecovery() {
        let points: [CGPoint] = [[0, 0], [2, 0], [2, 1], [0, 1]]
        let faces = [HalfEdgeTopology.FaceDefinition(outer: [0, 1, 2, 3])]
        let mesh = Mesh2D(points: points, faces: faces)

        let poly = mesh.polygon(for: HalfEdgeTopology.FaceID(raw: 0))
        #expect(poly.count == 4)
        #expect(mesh.isConvex(HalfEdgeTopology.FaceID(raw: 0)))
    }

    @Test("Triangle with dangling edge")
    func triangleWithDanglingEdge() {
        let segments: [Identified<String, LineSegment>] = [
            Identified(id: "AB", value: LineSegment([0, 0], [2, 0])),
            Identified(id: "BC", value: LineSegment([2, 0], [1, 2])),
            Identified(id: "CA", value: LineSegment([1, 2], [0, 0])),
            Identified(id: "AD", value: LineSegment([0, 0], [-1, -1]))
        ]

        let mesh = Mesh2D(segments: segments)

        #expect(mesh.topology.validate().isEmpty)
        #expect(mesh.topology.vertices.count == 4)
        #expect(mesh.topology.halfEdges.count == 8)
        #expect(mesh.topology.faces.count >= 1, "At least the triangle face exists")

        for vertex in mesh.topology.vertices {
            #expect(vertex.edge != nil)
        }
        // Twins are symmetric.
        for edge in mesh.topology.halfEdges {
            if let twinID = edge.twin {
                #expect(mesh.topology.halfEdges[twinID.raw].twin == edge.id)
            }
        }
    }

    @Test("Hourglass — two triangles sharing a vertex")
    func hourglass() {
        let segments: [Identified<String, LineSegment>] = [
            Identified(id: "CA", value: LineSegment([0, 0], [-1, 1])),
            Identified(id: "AB", value: LineSegment([-1, 1], [1, 1])),
            Identified(id: "BC", value: LineSegment([1, 1], [0, 0])),
            Identified(id: "CD", value: LineSegment([0, 0], [-1, -1])),
            Identified(id: "DE", value: LineSegment([-1, -1], [1, -1])),
            Identified(id: "EC", value: LineSegment([1, -1], [0, 0]))
        ]

        let mesh = Mesh2D(segments: segments)

        #expect(mesh.topology.validate().isEmpty)
        #expect(mesh.topology.vertices.count == 5)
        #expect(mesh.topology.halfEdges.count == 12)
        #expect(mesh.topology.faces.count == 3)

        let interior = mesh.topology.faces.filter { (mesh.signedArea($0.id) ?? 0) < 0 }
        #expect(interior.count == 2)
        for face in interior {
            let area = mesh.signedArea(face.id) ?? 0
            #expect(abs(abs(area) - 1.0) < 0.01)
        }

        // The shared vertex at origin has ≥ 4 outgoing edges.
        let center = mesh.topology.vertices.first { v in
            let p = mesh.point(v.id)
            return abs(p.x) < 0.01 && abs(p.y) < 0.01
        }
        #expect(center != nil)
        if let center {
            let outgoing = mesh.topology.halfEdges.filter { $0.origin == center.id }.count
            #expect(outgoing >= 4)
        }
    }

    @Test("Two triangles connected by a bridge segment")
    func twoTrianglesWithBridge() {
        let segments: [Identified<String, LineSegment>] = [
            Identified(id: "AB", value: LineSegment([-3, 0], [-1, 0])),
            Identified(id: "BC", value: LineSegment([-1, 0], [-2, 2])),
            Identified(id: "CA", value: LineSegment([-2, 2], [-3, 0])),
            Identified(id: "DE", value: LineSegment([1, 0], [3, 0])),
            Identified(id: "EF", value: LineSegment([3, 0], [2, 2])),
            Identified(id: "FD", value: LineSegment([2, 2], [1, 0])),
            Identified(id: "BD", value: LineSegment([-1, 0], [1, 0]))
        ]

        let mesh = Mesh2D(segments: segments)

        #expect(mesh.topology.validate().isEmpty)
        #expect(mesh.topology.vertices.count == 6)
        #expect(mesh.topology.halfEdges.count == 14)
        #expect(mesh.topology.faces.count == 3)

        let interior = mesh.topology.faces.filter { (mesh.signedArea($0.id) ?? 0) < 0 }
        #expect(interior.count == 2)
        for face in interior {
            let area = mesh.signedArea(face.id) ?? 0
            #expect(abs(abs(area) - 2.0) < 0.01, "Each triangle has area ≈ 2")
        }
    }

    @Test("boundaryLoops returns the exterior loop for a single triangle")
    func boundaryLoopsTriangle() {
        // Indexed triangle: half-edges have no twins, so they are all boundary.
        let points: [CGPoint] = [[0, 0], [1, 0], [0.5, 1]]
        let faces = [HalfEdgeTopology.FaceDefinition(outer: [0, 1, 2])]
        let mesh = Mesh2D(points: points, faces: faces)

        let loops = mesh.boundaryLoops()
        #expect(loops.count == 1)
        #expect(loops.first?.count == 3)
    }

    @Test("isHole flags CW-wound face")
    func isHoleFlagsCW() {
        // Square wound clockwise → signed area negative → treated as a hole.
        let points: [CGPoint] = [[0, 0], [0, 1], [1, 1], [1, 0]]
        let faces = [HalfEdgeTopology.FaceDefinition(outer: [0, 1, 2, 3])]
        let mesh = Mesh2D(points: points, faces: faces)

        let fID = HalfEdgeTopology.FaceID(raw: 0)
        #expect(mesh.isHole(fID))
        #expect((mesh.signedArea(fID) ?? 0) < 0)
    }

    @Test("undirectedEdges returns one triple per undirected edge")
    func undirectedEdgesCount() {
        let points: [CGPoint] = [[0, 0], [1, 0], [0.5, 1]]
        let faces = [HalfEdgeTopology.FaceDefinition(outer: [0, 1, 2])]
        let mesh = Mesh2D(points: points, faces: faces)

        let edges = mesh.undirectedEdges()
        #expect(edges.count == 3)
        // swiftlint:disable:next prefer_key_path
        #expect(Set(edges.map { $0.2 }) == Set([0, 1, 2]))
    }

    @Test("Face with hole — polygon and holePolygons")
    func faceWithHole() {
        // Outer square + inner square hole (CW hole winding).
        let points: [CGPoint] = [
            [0, 0], [4, 0], [4, 4], [0, 4],     // outer (CCW)
            [1, 1], [1, 3], [3, 3], [3, 1]      // hole (CW when listed 4→5→6→7)
        ]
        let faces = [HalfEdgeTopology.FaceDefinition(outer: [0, 1, 2, 3], holes: [[4, 5, 6, 7]])]
        let mesh = Mesh2D(points: points, faces: faces)

        let fID = HalfEdgeTopology.FaceID(raw: 0)
        #expect(mesh.polygon(for: fID).count == 4)
        let holes = mesh.holePolygons(for: fID)
        #expect(holes.count == 1)
        #expect(holes.first?.count == 4)
    }

    @Test("deleteEdge on interior edge merges two faces")
    func deleteInteriorEdgeMergesFaces() {
        // Diamond split by the N→S diagonal: 2 interior faces.
        let segments: [Identified<String, LineSegment>] = [
            Identified(id: "NE", value: LineSegment([0, 1], [1, 0])),
            Identified(id: "ES", value: LineSegment([1, 0], [0, -1])),
            Identified(id: "SW", value: LineSegment([0, -1], [-1, 0])),
            Identified(id: "WN", value: LineSegment([-1, 0], [0, 1])),
            Identified(id: "NS", value: LineSegment([0, 1], [0, -1]))
        ]

        var mesh = Mesh2D(segments: segments)

        let interiorBefore = mesh.topology.faces.filter { (mesh.signedArea($0.id) ?? 0) < 0 }.count
        #expect(interiorBefore == 2)

        mesh.deleteEdge(label: "NS")

        // After merging, exactly one interior face should remain (edge pointer non-nil),
        // and the merged face should cover the full diamond (|area| ≈ 2).
        let remainingInterior = mesh.topology.faces.filter { face in
            face.edge != nil && (mesh.signedArea(face.id) ?? 0) < 0
        }
        #expect(remainingInterior.count == 1)
        if let area = remainingInterior.first.flatMap({ mesh.signedArea($0.id) }) {
            #expect(abs(abs(area) - 2.0) < 0.01)
        }
    }

    @Test("neighborFaces crosses twins")
    func neighborFacesAcrossDiagonal() {
        // Two adjacent indexed triangles sharing edge 1→2 (as 2→1 in the second face).
        // Face A: 0,1,2 ; Face B: 2,1,3 (so diagonal is shared, opposite direction).
        let points: [CGPoint] = [[0, 0], [1, 0], [0, 1], [1, 1]]
        let faces = [
            HalfEdgeTopology.FaceDefinition(outer: [0, 1, 2]),
            HalfEdgeTopology.FaceDefinition(outer: [2, 1, 3])
        ]
        let mesh = Mesh2D(points: points, faces: faces)

        let neighbors = mesh.topology.neighborFaces(of: HalfEdgeTopology.FaceID(raw: 0))
        #expect(neighbors == [HalfEdgeTopology.FaceID(raw: 1)])
    }
}
