import CoreGraphics
import Testing
@testable import SwiftMesh

// MARK: - Helpers

/// Make a simple unit square from segments: (0,0)→(1,0)→(1,1)→(0,1)→(0,0)
private func makeSquareSegments() -> [Identified<String, LineSegment>] {
    let p0 = CGPoint(x: 0, y: 0)
    let p1 = CGPoint(x: 1, y: 0)
    let p2 = CGPoint(x: 1, y: 1)
    let p3 = CGPoint(x: 0, y: 1)
    return [
        Identified(id: "bottom", value: LineSegment(start: p0, end: p1)),
        Identified(id: "right", value: LineSegment(start: p1, end: p2)),
        Identified(id: "top", value: LineSegment(start: p2, end: p3)),
        Identified(id: "left", value: LineSegment(start: p3, end: p0)),
    ]
}

/// Make a triangle from segments.
private func makeTriangleSegments() -> [Identified<String, LineSegment>] {
    let p0 = CGPoint(x: 0, y: 0)
    let p1 = CGPoint(x: 1, y: 0)
    let p2 = CGPoint(x: 0.5, y: 1)
    return [
        Identified(id: "base", value: LineSegment(start: p0, end: p1)),
        Identified(id: "right", value: LineSegment(start: p1, end: p2)),
        Identified(id: "left", value: LineSegment(start: p2, end: p0)),
    ]
}

/// Make two adjacent triangles sharing an edge: a "bowtie" or diamond shape.
/// Triangle 1: (0,0)→(1,0)→(0.5,1)
/// Triangle 2: (1,0)→(2,0)→(1,1)  (shares no edge — separate)
/// Actually let's do two triangles sharing edge (1,0)→(0.5,1):
/// T1: (0,0)→(1,0)→(0.5,1)
/// T2: (1,0)→(1.5,1)→(0.5,1)  — shares edge differently
/// Simplest: a square split by a diagonal.
private func makeSquareWithDiagonalSegments() -> [Identified<String, LineSegment>] {
    let p0 = CGPoint(x: 0, y: 0)
    let p1 = CGPoint(x: 1, y: 0)
    let p2 = CGPoint(x: 1, y: 1)
    let p3 = CGPoint(x: 0, y: 1)
    return [
        Identified(id: "bottom", value: LineSegment(start: p0, end: p1)),
        Identified(id: "right", value: LineSegment(start: p1, end: p2)),
        Identified(id: "diagonal", value: LineSegment(start: p2, end: p0)),
        Identified(id: "top", value: LineSegment(start: p2, end: p3)),
        Identified(id: "left", value: LineSegment(start: p3, end: p0)),
    ]
}

// MARK: - Segment-based construction tests

@Suite("HalfEdgeMesh — Segment Init")
struct HalfEdgeMeshSegmentTests {

    @Test("Triangle: correct vertex/edge/face counts")
    func triangleCounts() {
        let mesh = HalfEdgeMesh(segments: makeTriangleSegments())
        #expect(mesh.vertices.count == 3)
        // 3 segments × 2 half-edges each = 6
        #expect(mesh.halfEdges.count == 6)
        // Should have 2 faces: one interior CCW, one exterior CW
        #expect(mesh.faces.count == 2)
    }

    @Test("Triangle validates")
    func triangleValidates() {
        let mesh = HalfEdgeMesh(segments: makeTriangleSegments())
        #expect(mesh.validate() == nil)
    }

    @Test("Square: correct counts")
    func squareCounts() {
        let mesh = HalfEdgeMesh(segments: makeSquareSegments())
        #expect(mesh.vertices.count == 4)
        #expect(mesh.halfEdges.count == 8)
        #expect(mesh.faces.count == 2) // interior + exterior
    }

    @Test("Square validates")
    func squareValidates() {
        let mesh = HalfEdgeMesh(segments: makeSquareSegments())
        #expect(mesh.validate() == nil)
    }

    @Test("Square with diagonal: correct counts")
    func squareWithDiagonalCounts() {
        let mesh = HalfEdgeMesh(segments: makeSquareWithDiagonalSegments())
        #expect(mesh.vertices.count == 4)
        #expect(mesh.halfEdges.count == 10) // 5 segments × 2
        #expect(mesh.faces.count == 3) // 2 interior triangles + 1 exterior
    }

    @Test("Square with diagonal validates")
    func squareWithDiagonalValidates() {
        let mesh = HalfEdgeMesh(segments: makeSquareWithDiagonalSegments())
        #expect(mesh.validate() == nil)
    }

    @Test("All half-edges have twins")
    func allEdgesHaveTwins() {
        let mesh = HalfEdgeMesh(segments: makeSquareSegments())
        for he in mesh.halfEdges {
            #expect(he.twin != nil, "Half-edge \(he.id) should have a twin")
        }
    }

    @Test("Twin symmetry")
    func twinSymmetry() {
        let mesh = HalfEdgeMesh(segments: makeTriangleSegments())
        for he in mesh.halfEdges {
            guard let twin = he.twin else {
                continue
            }
            #expect(mesh.halfEdges[twin.raw].twin == he.id)
        }
    }

    @Test("Next/prev consistency")
    func nextPrevConsistency() {
        let mesh = HalfEdgeMesh(segments: makeSquareSegments())
        for he in mesh.halfEdges {
            if let next = he.next {
                #expect(mesh.halfEdges[next.raw].prev == he.id)
            }
            if let prev = he.prev {
                #expect(mesh.halfEdges[prev.raw].next == he.id)
            }
        }
    }

    @Test("Every vertex has an outgoing edge")
    func verticesHaveEdges() {
        let mesh = HalfEdgeMesh(segments: makeSquareSegments())
        for v in mesh.vertices {
            #expect(v.edge != nil, "Vertex \(v.id) should have an outgoing edge")
        }
    }

    @Test("Vertex outgoing edge originates from that vertex")
    func vertexEdgeOrigin() {
        let mesh = HalfEdgeMesh(segments: makeTriangleSegments())
        for v in mesh.vertices {
            guard let edgeID = v.edge else {
                continue
            }
            #expect(mesh.halfEdges[edgeID.raw].origin == v.id)
        }
    }
}

// MARK: - Face-definition (indexed) construction tests

@Suite("HalfEdgeMesh — Indexed Init")
struct HalfEdgeMeshIndexedTests {

    @Test("Single triangle from points/faces")
    func singleTriangle() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 0.5, y: 1),
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2])
        ])
        #expect(mesh.vertices.count == 3)
        #expect(mesh.faces.count == 1)
        // 3 edges in one face loop
        #expect(mesh.halfEdges.count == 3)
        #expect(mesh.validate() == nil)
    }

    @Test("Two adjacent triangles sharing an edge")
    func twoAdjacentTriangles() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 0, y: 1),
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2]),
            .init(outer: [0, 2, 3]),
        ])
        #expect(mesh.vertices.count == 4)
        #expect(mesh.faces.count == 2)
        // 3 edges per triangle = 6 half-edges, but shared edge has twin linking
        #expect(mesh.halfEdges.count == 6)
        #expect(mesh.validate() == nil)
    }

    @Test("Quad face")
    func quadFace() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 0, y: 1),
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2, 3])
        ])
        #expect(mesh.vertices.count == 4)
        #expect(mesh.faces.count == 1)
        #expect(mesh.halfEdges.count == 4)
        #expect(mesh.validate() == nil)
    }

    @Test("Face with hole")
    func faceWithHole() {
        // Outer square, inner square hole (wound opposite direction)
        let points = [
            // Outer: CCW
            CGPoint(x: 0, y: 0),   // 0
            CGPoint(x: 4, y: 0),   // 1
            CGPoint(x: 4, y: 4),   // 2
            CGPoint(x: 0, y: 4),   // 3
            // Inner hole: CW
            CGPoint(x: 1, y: 1),   // 4
            CGPoint(x: 1, y: 3),   // 5
            CGPoint(x: 3, y: 3),   // 6
            CGPoint(x: 3, y: 1),   // 7
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2, 3], holes: [[4, 5, 6, 7]])
        ])
        #expect(mesh.vertices.count == 8)
        #expect(mesh.faces.count == 1)
        #expect(mesh.faces[0].holeEdges.count == 1)
        #expect(mesh.validate() == nil)
    }

    @Test("Twin linking between adjacent indexed faces")
    func twinLinkingIndexed() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 0, y: 1),
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2]),
            .init(outer: [0, 2, 3]),
        ])

        // The shared edge 0→2 and 2→0 should be twins
        var twinCount = 0
        for he in mesh.halfEdges where he.twin != nil {
            twinCount += 1
        }
        // Exactly 2 half-edges should have twins (the shared edge pair)
        #expect(twinCount == 2)
    }

    @Test("Signed area is computed for indexed faces")
    func signedAreaIndexed() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 0, y: 1),
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2, 3])
        ])
        // CCW winding → positive signed area = 1.0
        #expect(mesh.faces[0].signedArea != nil)
        let area = mesh.faces[0].signedArea!
        #expect(abs(area - 1.0) < 1e-10)
    }
}

// MARK: - Face query tests

@Suite("HalfEdgeMesh — Face Queries")
struct HalfEdgeMeshFaceQueryTests {

    @Test("polygon(for:) returns correct points")
    func polygonForFace() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 2, y: 0),
            CGPoint(x: 2, y: 2),
            CGPoint(x: 0, y: 2),
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2, 3])
        ])
        let faceID = mesh.faces[0].id
        let poly = mesh.polygon(for: faceID)
        #expect(poly.count == 4)
    }

    @Test("vertexLoop(for:) returns correct vertex IDs")
    func vertexLoopForFace() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 0.5, y: 1),
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2])
        ])
        let loop = mesh.vertexLoop(for: mesh.faces[0].id)
        #expect(loop.count == 3)
        // Should be the same vertices we put in
        let rawIDs = Set(loop.map(\.raw))
        #expect(rawIDs == [0, 1, 2])
    }

    @Test("isConvex returns true for convex polygon")
    func isConvexSquare() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 0, y: 1),
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2, 3])
        ])
        #expect(mesh.isConvex(mesh.faces[0].id))
    }

    @Test("isConvex returns false for non-convex polygon")
    func isConvexLShape() {
        // An L-shaped polygon (non-convex)
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 2, y: 0),
            CGPoint(x: 2, y: 1),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 1, y: 2),
            CGPoint(x: 0, y: 2),
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2, 3, 4, 5])
        ])
        #expect(!mesh.isConvex(mesh.faces[0].id))
    }

    @Test("isHole detects negative signed area")
    func isHoleDetection() {
        // CW winding → negative area → hole
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0, y: 1),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 1, y: 0),
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2, 3])
        ])
        let face = mesh.faces[0]
        if let area = face.signedArea, area < 0 {
            #expect(mesh.isHole(face.id))
        } else {
            #expect(!mesh.isHole(face.id))
        }
    }

    @Test("neighborFaces returns adjacent faces")
    func neighborFaces() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 0, y: 1),
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2]),
            .init(outer: [0, 2, 3]),
        ])
        let neighbors0 = mesh.neighborFaces(of: mesh.faces[0].id)
        let neighbors1 = mesh.neighborFaces(of: mesh.faces[1].id)
        #expect(neighbors0.contains(mesh.faces[1].id))
        #expect(neighbors1.contains(mesh.faces[0].id))
    }

    @Test("holePolygons returns hole boundaries")
    func holePolygons() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 4, y: 0),
            CGPoint(x: 4, y: 4),
            CGPoint(x: 0, y: 4),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 1, y: 3),
            CGPoint(x: 3, y: 3),
            CGPoint(x: 3, y: 1),
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2, 3], holes: [[4, 5, 6, 7]])
        ])
        let holes = mesh.holePolygons(for: mesh.faces[0].id)
        #expect(holes.count == 1)
        #expect(holes[0].count == 4)
    }
}

// MARK: - Undirected edges

@Suite("HalfEdgeMesh — Undirected Edges")
struct HalfEdgeMeshUndirectedEdgeTests {

    @Test("undirectedEdges count for triangle")
    func triangleUndirectedEdges() {
        let mesh = HalfEdgeMesh(segments: makeTriangleSegments())
        let edges = mesh.undirectedEdges()
        #expect(edges.count == 3)
    }

    @Test("undirectedEdges count for square")
    func squareUndirectedEdges() {
        let mesh = HalfEdgeMesh(segments: makeSquareSegments())
        let edges = mesh.undirectedEdges()
        #expect(edges.count == 4)
    }

    @Test("undirectedEdges segment IDs are unique")
    func undirectedEdgesUniqueIDs() {
        let mesh = HalfEdgeMesh(segments: makeSquareWithDiagonalSegments())
        let edges = mesh.undirectedEdges()
        let ids = edges.map(\.2)
        #expect(Set(ids).count == ids.count)
    }
}

// MARK: - Edge deletion

@Suite("HalfEdgeMesh — Edge Deletion")
struct HalfEdgeMeshEdgeDeletionTests {

    @Test("Delete diagonal merges two faces")
    func deleteDiagonalMergesFaces() {
        var mesh = HalfEdgeMesh(segments: makeSquareWithDiagonalSegments())
        let faceCountBefore = mesh.faces.filter { $0.edge != nil }.count
        #expect(faceCountBefore == 3) // 2 interior + 1 exterior

        mesh.deleteEdge(segmentID: "diagonal")

        // After deleting the diagonal, the two interior triangles should merge
        let activeFaces = mesh.faces.filter { $0.edge != nil }
        #expect(activeFaces.count == 2) // 1 merged interior + 1 exterior
    }

    @Test("Delete boundary edge")
    func deleteBoundaryEdge() {
        // For segment-based mesh, all edges have twins, so this tests
        // deleting an edge on the outer boundary
        var mesh = HalfEdgeMesh(segments: makeSquareSegments())
        #expect(mesh.validate() == nil)
        mesh.deleteEdge(segmentID: "bottom")
        // The mesh should still have vertices
        #expect(mesh.vertices.count == 4)
    }

    @Test("Delete non-existent edge is a no-op")
    func deleteNonExistentEdge() {
        var mesh = HalfEdgeMesh(segments: makeSquareSegments())
        let facesBefore = mesh.faces.count
        let hesBefore = mesh.halfEdges.count
        mesh.deleteEdge(segmentID: "nonexistent")
        #expect(mesh.faces.count == facesBefore)
        #expect(mesh.halfEdges.count == hesBefore)
    }
}

// MARK: - Accessors

@Suite("HalfEdgeMesh — Accessors")
struct HalfEdgeMeshAccessorTests {

    @Test("point() returns correct coordinates")
    func pointAccessor() {
        let points = [
            CGPoint(x: 3, y: 7),
            CGPoint(x: 5, y: 11),
            CGPoint(x: 9, y: 2),
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2])
        ])
        let vID = HalfEdgeMesh<Int>.VertexID(raw: 1)
        let p = mesh.point(vID)
        #expect(p.x == 5)
        #expect(p.y == 11)
    }

    @Test("dest(of:) returns correct destination")
    func destAccessor() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1),
            CGPoint(x: 0, y: 1),
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2]),
            .init(outer: [0, 2, 3]),
        ])
        // Find a half-edge with a twin and check dest
        for he in mesh.halfEdges where he.twin != nil {
            let d = mesh.dest(of: he.id)
            #expect(d != nil)
            #expect(d != he.origin)
        }
    }
}

// MARK: - Description conformances

@Suite("HalfEdgeMesh — CustomStringConvertible")
struct HalfEdgeMeshDescriptionTests {

    @Test("ID descriptions")
    func idDescriptions() {
        let v = HalfEdgeMesh<Int>.VertexID(raw: 42)
        let h = HalfEdgeMesh<Int>.HalfEdgeID(raw: 7)
        let f = HalfEdgeMesh<Int>.FaceID(raw: 3)
        #expect(v.description == "V42")
        #expect(h.description == "H7")
        #expect(f.description == "F3")
    }
}

// MARK: - Signed area (via faces)

@Suite("HalfEdgeMesh — Signed Area")
struct HalfEdgeMeshSignedAreaTests {

    @Test("CCW square has positive signed area")
    func ccwSquarePositiveArea() {
        let mesh = HalfEdgeMesh(segments: makeSquareSegments())
        let positiveFaces = mesh.faces.filter { ($0.signedArea ?? 0) > 0 }
        #expect(!positiveFaces.isEmpty)
    }

    @Test("Segment-based mesh has both positive and negative area faces")
    func segmentMeshBothAreas() {
        let mesh = HalfEdgeMesh(segments: makeSquareSegments())
        let areas = mesh.faces.compactMap(\.signedArea)
        let hasPositive = areas.contains { $0 > 0 }
        let hasNegative = areas.contains { $0 < 0 }
        // Interior face should be positive, exterior should be negative
        #expect(hasPositive)
        #expect(hasNegative)
    }

    @Test("Unit square interior face area is 1.0")
    func unitSquareArea() {
        let mesh = HalfEdgeMesh(segments: makeSquareSegments())
        let areas = mesh.faces.compactMap(\.signedArea)
        let positiveArea = areas.filter { $0 > 0 }
        #expect(positiveArea.count == 1)
        #expect(abs(positiveArea[0] - 1.0) < 1e-10)
    }
}
