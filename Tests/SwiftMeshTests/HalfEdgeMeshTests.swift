import CoreGraphics
import Geometry
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

/// A square split by a diagonal.
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

// MARK: - Segment-based construction tests (2D / CGPoint)

@Suite("HalfEdgeMesh — Segment Init")
struct HalfEdgeMeshSegmentTests {

    @Test("Triangle: correct vertex/edge/face counts")
    func triangleCounts() {
        let mesh = HalfEdgeMesh(segments: makeTriangleSegments())
        #expect(mesh.vertices.count == 3)
        #expect(mesh.halfEdges.count == 6)
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
        #expect(mesh.faces.count == 2)
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
        #expect(mesh.halfEdges.count == 10)
        #expect(mesh.faces.count == 3)
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

@Suite("HalfEdgeMesh — Indexed Init (CGPoint)")
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
        var twinCount = 0
        for he in mesh.halfEdges where he.twin != nil {
            twinCount += 1
        }
        #expect(twinCount == 2)
    }

    @Test("Signed area via method for indexed faces")
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
        let area = mesh.signedArea(of: mesh.faces[0].id)
        #expect(area != nil)
        #expect(abs(area! - 1.0) < 1e-10)
    }
}

// MARK: - Indexed Init with SIMD3<Float> (3D)

@Suite("HalfEdgeMesh — Indexed Init (SIMD3<Float>)")
struct HalfEdgeMeshIndexed3DTests {

    @Test("Single triangle in 3D")
    func singleTriangle3D() {
        let points: [SIMD3<Float>] = [
            SIMD3(0, 0, 0),
            SIMD3(1, 0, 0),
            SIMD3(0, 1, 0),
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2])
        ])
        #expect(mesh.vertices.count == 3)
        #expect(mesh.faces.count == 1)
        #expect(mesh.halfEdges.count == 3)
        #expect(mesh.validate() == nil)
    }

    @Test("Quad in 3D")
    func quad3D() {
        let points: [SIMD3<Float>] = [
            SIMD3(0, 0, 0),
            SIMD3(1, 0, 0),
            SIMD3(1, 1, 0),
            SIMD3(0, 1, 0),
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2, 3])
        ])
        #expect(mesh.vertices.count == 4)
        #expect(mesh.faces.count == 1)
        #expect(mesh.halfEdges.count == 4)
        #expect(mesh.validate() == nil)
    }

    @Test("Two adjacent triangles in 3D with twin linking")
    func adjacentTriangles3D() {
        let points: [SIMD3<Float>] = [
            SIMD3(0, 0, 0),
            SIMD3(1, 0, 0),
            SIMD3(1, 1, 0),
            SIMD3(0, 1, 0),
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2]),
            .init(outer: [0, 2, 3]),
        ])
        #expect(mesh.vertices.count == 4)
        #expect(mesh.faces.count == 2)
        #expect(mesh.halfEdges.count == 6)
        #expect(mesh.validate() == nil)

        var twinCount = 0
        for he in mesh.halfEdges where he.twin != nil {
            twinCount += 1
        }
        #expect(twinCount == 2)
    }

    @Test("Non-planar quad in 3D still works topologically")
    func nonPlanarQuad3D() {
        // Intentionally non-planar: fourth vertex off the plane
        let points: [SIMD3<Float>] = [
            SIMD3(0, 0, 0),
            SIMD3(1, 0, 0),
            SIMD3(1, 1, 0),
            SIMD3(0, 1, 0.5), // off-plane
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2, 3])
        ])
        #expect(mesh.vertices.count == 4)
        #expect(mesh.faces.count == 1)
        #expect(mesh.validate() == nil)
    }

    @Test("polygon(for:) returns 3D points")
    func polygon3D() {
        let points: [SIMD3<Float>] = [
            SIMD3(0, 0, 0),
            SIMD3(1, 0, 0),
            SIMD3(0.5, 1, 0),
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2])
        ])
        let poly = mesh.polygon(for: mesh.faces[0].id)
        #expect(poly.count == 3)
    }

    @Test("vertexLoop in 3D")
    func vertexLoop3D() {
        let points: [SIMD3<Float>] = [
            SIMD3(0, 0, 0),
            SIMD3(1, 0, 0),
            SIMD3(0.5, 1, 0),
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2])
        ])
        let loop = mesh.vertexLoop(for: mesh.faces[0].id)
        #expect(loop.count == 3)
        let rawIDs = Set(loop.map(\.raw))
        #expect(rawIDs == [0, 1, 2])
    }

    @Test("neighborFaces in 3D")
    func neighborFaces3D() {
        let points: [SIMD3<Float>] = [
            SIMD3(0, 0, 0),
            SIMD3(1, 0, 0),
            SIMD3(1, 1, 0),
            SIMD3(0, 1, 0),
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2]),
            .init(outer: [0, 2, 3]),
        ])
        let neighbors = mesh.neighborFaces(of: mesh.faces[0].id)
        #expect(neighbors.contains(mesh.faces[1].id))
    }

    @Test("Face with hole in 3D")
    func faceWithHole3D() {
        let points: [SIMD3<Float>] = [
            SIMD3(0, 0, 0),
            SIMD3(4, 0, 0),
            SIMD3(4, 4, 0),
            SIMD3(0, 4, 0),
            SIMD3(1, 1, 0),
            SIMD3(1, 3, 0),
            SIMD3(3, 3, 0),
            SIMD3(3, 1, 0),
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2, 3], holes: [[4, 5, 6, 7]])
        ])
        #expect(mesh.faces.count == 1)
        #expect(mesh.faces[0].holeEdges.count == 1)
        #expect(mesh.validate() == nil)
    }
}

// MARK: - Face query tests (2D-specific)

@Suite("HalfEdgeMesh — Face Queries (2D)")
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
        let poly = mesh.polygon(for: mesh.faces[0].id)
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

    @Test("isHole detects CW winding")
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
        let area = mesh.signedArea(of: mesh.faces[0].id)
        if let area, area < 0 {
            #expect(mesh.isHole(mesh.faces[0].id))
        } else {
            #expect(!mesh.isHole(mesh.faces[0].id))
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
        #expect(faceCountBefore == 3)

        mesh.deleteEdge(segmentID: "diagonal")

        let activeFaces = mesh.faces.filter { $0.edge != nil }
        #expect(activeFaces.count == 2)
    }

    @Test("Delete boundary edge")
    func deleteBoundaryEdge() {
        var mesh = HalfEdgeMesh(segments: makeSquareSegments())
        #expect(mesh.validate() == nil)
        mesh.deleteEdge(segmentID: "bottom")
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

    @Test("point() returns correct coordinates (2D)")
    func pointAccessor2D() {
        let points = [
            CGPoint(x: 3, y: 7),
            CGPoint(x: 5, y: 11),
            CGPoint(x: 9, y: 2),
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2])
        ])
        let vID = HalfEdgeMesh<Int, CGPoint>.VertexID(raw: 1)
        let p = mesh.point(vID)
        #expect(p.x == 5)
        #expect(p.y == 11)
    }

    @Test("point() returns correct coordinates (3D)")
    func pointAccessor3D() {
        let points: [SIMD3<Float>] = [
            SIMD3(3, 7, 1),
            SIMD3(5, 11, 2),
            SIMD3(9, 2, 3),
        ]
        let mesh = HalfEdgeMesh(points: points, faces: [
            .init(outer: [0, 1, 2])
        ])
        let vID = HalfEdgeMesh<Int, SIMD3<Float>>.VertexID(raw: 1)
        let p = mesh.point(vID)
        #expect(p.x == 5)
        #expect(p.y == 11)
        #expect(p.z == 2)
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
        let v = HalfEdgeMesh<Int, CGPoint>.VertexID(raw: 42)
        let h = HalfEdgeMesh<Int, CGPoint>.HalfEdgeID(raw: 7)
        let f = HalfEdgeMesh<Int, CGPoint>.FaceID(raw: 3)
        #expect(v.description == "V42")
        #expect(h.description == "H7")
        #expect(f.description == "F3")
    }
}

// MARK: - Signed area (2D only)

@Suite("HalfEdgeMesh — Signed Area")
struct HalfEdgeMeshSignedAreaTests {

    @Test("CCW square has positive signed area")
    func ccwSquarePositiveArea() {
        let mesh = HalfEdgeMesh(segments: makeSquareSegments())
        let positiveFaces = mesh.faces.filter {
            guard let area = mesh.signedArea(of: $0.id) else {
                return false
            }
            return area > 0
        }
        #expect(!positiveFaces.isEmpty)
    }

    @Test("Segment-based mesh has both positive and negative area faces")
    func segmentMeshBothAreas() {
        let mesh = HalfEdgeMesh(segments: makeSquareSegments())
        let areas = mesh.faces.compactMap { mesh.signedArea(of: $0.id) }
        let hasPositive = areas.contains { $0 > 0 }
        let hasNegative = areas.contains { $0 < 0 }
        #expect(hasPositive)
        #expect(hasNegative)
    }

    @Test("Unit square interior face area is 1.0")
    func unitSquareArea() {
        let mesh = HalfEdgeMesh(segments: makeSquareSegments())
        let areas = mesh.faces.compactMap { mesh.signedArea(of: $0.id) }
        let positiveAreas = areas.filter { $0 > 0 }
        #expect(positiveAreas.count == 1)
        #expect(abs(positiveAreas[0] - 1.0) < 1e-10)
    }
}
