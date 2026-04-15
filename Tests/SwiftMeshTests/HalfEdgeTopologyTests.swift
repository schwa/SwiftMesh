@testable import SwiftMesh
import Testing

// MARK: - Helpers

private func makeTriangleTopology() -> HalfEdgeTopology {
    HalfEdgeTopology(vertexCount: 3, faces: [.init(outer: [0, 1, 2])])
}

private func makeQuadTopology() -> HalfEdgeTopology {
    HalfEdgeTopology(vertexCount: 4, faces: [.init(outer: [0, 1, 2, 3])])
}

private func makeTwoTrianglesTopology() -> HalfEdgeTopology {
    // Two triangles sharing edge 0→2
    HalfEdgeTopology(vertexCount: 4, faces: [
        .init(outer: [0, 1, 2]),
        .init(outer: [0, 2, 3])
    ])
}

private func makeQuadWithHoleTopology() -> HalfEdgeTopology {
    // Outer quad (4 verts) + inner hole quad (4 verts)
    HalfEdgeTopology(vertexCount: 8, faces: [
        .init(outer: [0, 1, 2, 3], holes: [[4, 5, 6, 7]])
    ])
}

// MARK: - Construction

@Suite("HalfEdgeTopology — Construction")
struct HalfEdgeTopologyConstructionTests {
    @Test("Triangle: correct counts")
    func triangleCounts() {
        let topo = makeTriangleTopology()
        #expect(topo.vertices.count == 3)
        #expect(topo.halfEdges.count == 3)
        #expect(topo.faces.count == 1)
    }

    @Test("Triangle validates")
    func triangleValidates() {
        #expect(makeTriangleTopology().validate() == nil)
    }

    @Test("Quad: correct counts")
    func quadCounts() {
        let topo = makeQuadTopology()
        #expect(topo.vertices.count == 4)
        #expect(topo.halfEdges.count == 4)
        #expect(topo.faces.count == 1)
    }

    @Test("Quad validates")
    func quadValidates() {
        #expect(makeQuadTopology().validate() == nil)
    }

    @Test("Two adjacent triangles: correct counts")
    func twoTrianglesCounts() {
        let topo = makeTwoTrianglesTopology()
        #expect(topo.vertices.count == 4)
        #expect(topo.halfEdges.count == 6)
        #expect(topo.faces.count == 2)
    }

    @Test("Two adjacent triangles validates")
    func twoTrianglesValidates() {
        #expect(makeTwoTrianglesTopology().validate() == nil)
    }

    @Test("Face with hole: correct counts")
    func holeTopology() {
        let topo = makeQuadWithHoleTopology()
        #expect(topo.vertices.count == 8)
        #expect(topo.faces.count == 1)
        #expect(topo.faces[0].holeEdges.count == 1)
        #expect(topo.validate() == nil)
    }

    @Test("Twin linking between adjacent faces")
    func twinLinking() {
        let topo = makeTwoTrianglesTopology()
        var twinCount = 0
        for he in topo.halfEdges where he.twin != nil {
            twinCount += 1
        }
        #expect(twinCount == 2)
    }

    @Test("Twin symmetry")
    func twinSymmetry() {
        let topo = makeTwoTrianglesTopology()
        for he in topo.halfEdges {
            guard let twin = he.twin else {
                continue
            }
            #expect(topo.halfEdges[twin.raw].twin == he.id)
        }
    }

    @Test("Next/prev consistency")
    func nextPrevConsistency() {
        let topo = makeQuadTopology()
        for he in topo.halfEdges {
            if let next = he.next {
                #expect(topo.halfEdges[next.raw].prev == he.id)
            }
            if let prev = he.prev {
                #expect(topo.halfEdges[prev.raw].next == he.id)
            }
        }
    }

    @Test("Every vertex has an outgoing edge")
    func verticesHaveEdges() {
        let topo = makeQuadTopology()
        for vertex in topo.vertices {
            #expect(vertex.edge != nil)
        }
    }

    @Test("Vertex outgoing edge originates from that vertex")
    func vertexEdgeOrigin() {
        let topo = makeTriangleTopology()
        for vertex in topo.vertices {
            guard let edgeID = vertex.edge else {
                continue
            }
            #expect(topo.halfEdges[edgeID.raw].origin == vertex.id)
        }
    }
}

// MARK: - Topology queries

@Suite("HalfEdgeTopology — Queries")
struct HalfEdgeTopologyQueryTests {
    @Test("vertexLoop returns correct IDs")
    func vertexLoop() {
        let topo = makeTriangleTopology()
        let loop = topo.vertexLoop(for: topo.faces[0].id)
        #expect(loop.count == 3)
        let rawIDs = Set(loop.map(\.raw))
        #expect(rawIDs == [0, 1, 2])
    }

    @Test("halfEdgeLoop returns correct count")
    func halfEdgeLoop() {
        let topo = makeQuadTopology()
        let loop = topo.halfEdgeLoop(for: topo.faces[0].id)
        #expect(loop.count == 4)
    }

    @Test("holeVertexLoops returns hole boundaries")
    func holeVertexLoops() {
        let topo = makeQuadWithHoleTopology()
        let holes = topo.holeVertexLoops(for: topo.faces[0].id)
        #expect(holes.count == 1)
        #expect(holes[0].count == 4)
    }

    @Test("neighborFaces returns adjacent faces")
    func neighborFaces() {
        let topo = makeTwoTrianglesTopology()
        let neighbors0 = topo.neighborFaces(of: topo.faces[0].id)
        let neighbors1 = topo.neighborFaces(of: topo.faces[1].id)
        #expect(neighbors0.contains(topo.faces[1].id))
        #expect(neighbors1.contains(topo.faces[0].id))
    }

    @Test("undirectedEdges count for triangle")
    func undirectedEdgesTriangle() {
        let topo = makeTriangleTopology()
        #expect(topo.undirectedEdges().count == 3)
    }

    @Test("undirectedEdges count for two triangles")
    func undirectedEdgesTwoTriangles() {
        let topo = makeTwoTrianglesTopology()
        #expect(topo.undirectedEdges().count == 5)
    }

    @Test("dest(of:) returns correct destination")
    func destAccessor() {
        let topo = makeTwoTrianglesTopology()
        for he in topo.halfEdges where he.twin != nil {
            let dest = topo.dest(of: he.id)
            #expect(dest != nil)
            #expect(dest != he.origin)
        }
    }

    @Test("destViaNext(of:) returns correct destination")
    func destViaNextAccessor() {
        let topo = makeTriangleTopology()
        for he in topo.halfEdges {
            let dest = topo.destViaNext(of: he.id)
            #expect(dest != nil)
            #expect(dest != he.origin)
        }
    }
}

// MARK: - Edge deletion

@Suite("HalfEdgeTopology — Edge Deletion")
struct HalfEdgeTopologyEdgeDeletionTests {
    @Test("Delete shared edge merges two faces")
    func deleteSharedEdge() {
        var topo = makeTwoTrianglesTopology()
        let activeBefore = topo.faces.filter { $0.edge != nil }.count
        #expect(activeBefore == 2)

        // Find a half-edge on the shared edge (one with a twin)
        let sharedHE = topo.halfEdges.first { $0.twin != nil }!
        topo.deleteEdge(sharedHE.id)

        let activeAfter = topo.faces.filter { $0.edge != nil }.count
        #expect(activeAfter == 1)
    }

    @Test("Delete non-shared edge")
    func deleteNonSharedEdge() {
        var topo = makeTriangleTopology()
        #expect(topo.validate() == nil)
        // All edges in a single triangle have no twin
        let heID = topo.halfEdges[0].id
        topo.deleteEdge(heID)
        #expect(topo.vertices.count == 3)
    }
}

// MARK: - Description conformances

@Suite("HalfEdgeTopology — CustomStringConvertible")
struct HalfEdgeTopologyDescriptionTests {
    @Test("ID descriptions")
    func idDescriptions() {
        let vertex = HalfEdgeTopology.VertexID(raw: 42)
        let halfEdge = HalfEdgeTopology.HalfEdgeID(raw: 7)
        let face = HalfEdgeTopology.FaceID(raw: 3)
        #expect(vertex.description == "V42")
        #expect(halfEdge.description == "H7")
        #expect(face.description == "F3")
    }
}

// MARK: - Platonic solid topology (via Euler formula)

@Suite("HalfEdgeTopology — Euler Formula")
struct HalfEdgeTopologyEulerTests {
    @Test("Tetrahedron: V=4, E=6, F=4")
    func tetrahedron() {
        let topo = HalfEdgeTopology(vertexCount: 4, faces: [
            .init(outer: [0, 1, 2]),
            .init(outer: [0, 3, 1]),
            .init(outer: [0, 2, 3]),
            .init(outer: [1, 3, 2])
        ])
        #expect(topo.validate() == nil)
        #expect(topo.vertices.count == 4)
        #expect(topo.undirectedEdges().count == 6)
        #expect(topo.faces.count == 4)
        #expect(topo.vertices.count - topo.undirectedEdges().count + topo.faces.count == 2)
    }

    @Test("Cube: V=8, E=12, F=6")
    func cube() {
        let topo = HalfEdgeTopology(vertexCount: 8, faces: [
            .init(outer: [0, 3, 2, 1]),
            .init(outer: [4, 5, 6, 7]),
            .init(outer: [0, 1, 5, 4]),
            .init(outer: [3, 7, 6, 2]),
            .init(outer: [1, 2, 6, 5]),
            .init(outer: [0, 4, 7, 3])
        ])
        #expect(topo.validate() == nil)
        #expect(topo.vertices.count == 8)
        #expect(topo.undirectedEdges().count == 12)
        #expect(topo.faces.count == 6)
        #expect(topo.vertices.count - topo.undirectedEdges().count + topo.faces.count == 2)
    }
}
