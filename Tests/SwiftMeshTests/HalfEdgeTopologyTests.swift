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

// MARK: - Edge collapse

@Suite("HalfEdgeTopology — Edge Collapse")
struct HalfEdgeTopologyEdgeCollapseTests {
    // Helper: count live (non-tombstoned) faces
    private func liveFaces(_ topo: HalfEdgeTopology) -> [HalfEdgeTopology.Face] {
        topo.faces.filter { $0.edge != nil }
    }

    // Helper: count live vertices
    private func liveVertices(_ topo: HalfEdgeTopology) -> [HalfEdgeTopology.Vertex] {
        topo.vertices.filter { $0.edge != nil }
    }

    // Helper: count live half-edges
    private func liveHalfEdges(_ topo: HalfEdgeTopology) -> [HalfEdgeTopology.HalfEdge] {
        topo.halfEdges.filter { $0.next != nil }
    }

    // Helper: make a pyramid (4 triangles, 5 vertices, apex at index 4)
    private func makePyramid() -> HalfEdgeTopology {
        HalfEdgeTopology(vertexCount: 5, faces: [
            .init(outer: [0, 1, 4]),
            .init(outer: [1, 2, 4]),
            .init(outer: [2, 3, 4]),
            .init(outer: [3, 0, 4]),
        ])
    }

    // Helper: make a tetrahedron (closed mesh, 4 triangles, 4 vertices)
    private func makeTetrahedron() -> HalfEdgeTopology {
        HalfEdgeTopology(vertexCount: 4, faces: [
            .init(outer: [0, 1, 2]),
            .init(outer: [0, 3, 1]),
            .init(outer: [0, 2, 3]),
            .init(outer: [1, 3, 2]),
        ])
    }

    // Helper: make a triangle strip (3 triangles sharing edges)
    //   0---1---2---3
    //    \ | \ | \ |
    //     4   5   6
    private func makeTriangleStrip() -> HalfEdgeTopology {
        HalfEdgeTopology(vertexCount: 7, faces: [
            .init(outer: [0, 1, 4]),
            .init(outer: [1, 2, 5]),
            .init(outer: [2, 3, 6]),
        ])
    }

    // MARK: - Basic collapse on two triangles

    @Test("Collapse shared edge of two triangles returns surviving vertex")
    func collapseReturnsVertex() {
        var topo = makeTwoTrianglesTopology()
        let sharedHE = topo.halfEdges.first { $0.twin != nil }!
        let survivor = topo.collapseEdge(sharedHE.id)
        #expect(survivor != nil)
        #expect(survivor == sharedHE.origin)
    }

    @Test("Collapse shared edge of two triangles removes both faces")
    func collapseTwoTrianglesRemovesFaces() {
        var topo = makeTwoTrianglesTopology()
        let sharedHE = topo.halfEdges.first { $0.twin != nil }!
        topo.collapseEdge(sharedHE.id)
        #expect(liveFaces(topo).isEmpty)
    }

    @Test("Collapse shared edge of two triangles tombstones destination vertex")
    func collapseTombstonesDestVertex() {
        var topo = makeTwoTrianglesTopology()
        let sharedHE = topo.halfEdges.first { $0.twin != nil }!
        let destVertex = topo.destViaNext(of: sharedHE.id)!
        topo.collapseEdge(sharedHE.id)
        #expect(topo.vertices[destVertex.raw].edge == nil)
    }

    @Test("Collapse shared edge of two triangles: exactly one vertex is tombstoned")
    func collapseDecreasesVertexCount() {
        var topo = makeTwoTrianglesTopology()
        let sharedHE = topo.halfEdges.first { $0.twin != nil }!
        let dest = topo.destViaNext(of: sharedHE.id)!
        let origin = sharedHE.origin
        topo.collapseEdge(sharedHE.id)
        // Destination vertex is tombstoned
        #expect(topo.vertices[dest.raw].edge == nil)
        // Origin vertex survives (though it may have no live edges if all faces removed)
        // The key invariant: no live half-edge references the dead vertex
        for he in liveHalfEdges(topo) {
            #expect(he.origin != dest)
        }
        _ = origin // used above via sharedHE.origin
    }

    // MARK: - Pyramid collapse

    @Test("Collapse edge on pyramid reduces face count by 2")
    func collapsePyramidFaceCount() {
        var topo = makePyramid()
        let facesBefore = liveFaces(topo).count
        // Find a shared (interior) edge
        let sharedHE = topo.halfEdges.first { $0.twin != nil }!
        topo.collapseEdge(sharedHE.id)
        let facesAfter = liveFaces(topo).count
        #expect(facesAfter == facesBefore - 2)
    }

    @Test("Collapse edge on pyramid: remaining faces have valid loops")
    func collapsePyramidFaceLoops() {
        var topo = makePyramid()
        let sharedHE = topo.halfEdges.first { $0.twin != nil }!
        topo.collapseEdge(sharedHE.id)
        for face in liveFaces(topo) {
            let loop = topo.vertexLoop(for: face.id)
            #expect(loop.count >= 3)
        }
    }

    @Test("Collapse edge on pyramid: live vertex count decreases by 1")
    func collapsePyramidVertexCount() {
        var topo = makePyramid()
        let liveBeforeCount = liveVertices(topo).count
        let sharedHE = topo.halfEdges.first { $0.twin != nil }!
        topo.collapseEdge(sharedHE.id)
        #expect(liveVertices(topo).count == liveBeforeCount - 1)
    }

    // MARK: - Tetrahedron collapse

    @Test("Collapse edge on tetrahedron reduces faces from 4 to 2")
    func collapseTetrahedronFaceCount() {
        var topo = makeTetrahedron()
        #expect(liveFaces(topo).count == 4)
        let he = topo.halfEdges.first { $0.twin != nil }!
        topo.collapseEdge(he.id)
        #expect(liveFaces(topo).count == 2)
    }

    @Test("Collapse edge on tetrahedron: live vertices go from 4 to 3")
    func collapseTetrahedronVertexCount() {
        var topo = makeTetrahedron()
        #expect(liveVertices(topo).count == 4)
        let he = topo.halfEdges.first { $0.twin != nil }!
        topo.collapseEdge(he.id)
        #expect(liveVertices(topo).count == 3)
    }

    @Test("Collapse edge on tetrahedron: remaining faces have 3 vertices each")
    func collapseTetrahedronFaceLoops() {
        var topo = makeTetrahedron()
        let he = topo.halfEdges.first { $0.twin != nil }!
        topo.collapseEdge(he.id)
        for face in liveFaces(topo) {
            let loop = topo.vertexLoop(for: face.id)
            #expect(loop.count == 3)
        }
    }

    @Test("Collapse edge on tetrahedron: no vertex loops contain tombstoned vertex")
    func collapseTetrahedronNoDeadVertexInLoops() {
        var topo = makeTetrahedron()
        let he = topo.halfEdges.first { $0.twin != nil }!
        let dead = topo.destViaNext(of: he.id)!
        topo.collapseEdge(he.id)
        for face in liveFaces(topo) {
            let loop = topo.vertexLoop(for: face.id)
            #expect(!loop.contains(dead))
        }
    }

    // MARK: - Boundary edge collapse

    @Test("Collapse boundary edge (no twin) on single triangle")
    func collapseBoundaryEdge() {
        var topo = makeTriangleTopology()
        // All edges in a single triangle have no twin
        let he = topo.halfEdges[0]
        let dest = topo.destViaNext(of: he.id)!
        let survivor = topo.collapseEdge(he.id)
        #expect(survivor != nil)
        // Single triangle with collapsed edge → face becomes degenerate
        #expect(liveFaces(topo).isEmpty)
        // Destination vertex is tombstoned
        #expect(topo.vertices[dest.raw].edge == nil)
    }

    @Test("Collapse boundary edge on two triangles (non-shared edge)")
    func collapseBoundaryEdgeTwoTriangles() {
        var topo = makeTwoTrianglesTopology()
        // Find an edge with no twin (boundary)
        let boundaryHE = topo.halfEdges.first { $0.twin == nil }!
        let facesBefore = liveFaces(topo).count
        topo.collapseEdge(boundaryHE.id)
        // Should remove the face containing this edge
        #expect(liveFaces(topo).count == facesBefore - 1)
        // Dest vertex should be tombstoned
        let liveVerts = liveVertices(topo)
        #expect(liveVerts.count == 3)
    }

    // MARK: - Invalid collapse

    @Test("Collapse returns nil for half-edge with no destination")
    func collapseInvalidEdge() {
        var topo = makeTriangleTopology()
        // Collapse once to create tombstoned half-edges
        let he = topo.halfEdges[0]
        topo.collapseEdge(he.id)
        // Now try to collapse the same (now-dead) half-edge again
        let result = topo.collapseEdge(he.id)
        #expect(result == nil)
    }

    // MARK: - Sequential collapses

    @Test("Two sequential collapses on pyramid")
    func sequentialCollapses() {
        var topo = makePyramid()
        #expect(liveFaces(topo).count == 4)
        #expect(liveVertices(topo).count == 5)

        // First collapse
        let he1 = topo.halfEdges.first { $0.twin != nil && $0.next != nil }!
        topo.collapseEdge(he1.id)
        #expect(liveFaces(topo).count == 2)
        #expect(liveVertices(topo).count == 4)

        // Remaining faces should still have valid loops
        for face in liveFaces(topo) {
            let loop = topo.vertexLoop(for: face.id)
            #expect(loop.count >= 3)
        }

        // Second collapse
        if let he2 = topo.halfEdges.first(where: { $0.twin != nil && $0.next != nil }) {
            topo.collapseEdge(he2.id)
            #expect(liveFaces(topo).isEmpty)
        }
    }

    @Test("Sequential collapses on tetrahedron until minimal")
    func sequentialCollapsesTetrahedron() {
        var topo = makeTetrahedron()
        #expect(liveFaces(topo).count == 4)

        var collapseCount = 0
        while let he = topo.halfEdges.first(where: { $0.twin != nil && $0.next != nil }) {
            topo.collapseEdge(he.id)
            collapseCount += 1
            if collapseCount > 10 {
                break // safety valve
            }
        }
        // Should have collapsed multiple times
        #expect(collapseCount >= 2)
        // Eventually no more interior edges to collapse
    }

    // MARK: - Vertex loop correctness

    @Test("After collapse, surviving vertex appears in remaining face loops")
    func survivorInRemainingLoops() {
        var topo = makeTetrahedron()
        let he = topo.halfEdges.first { $0.twin != nil }!
        let survivor = topo.collapseEdge(he.id)!
        let remaining = liveFaces(topo)
        #expect(!remaining.isEmpty)
        for face in remaining {
            let loop = topo.vertexLoop(for: face.id)
            #expect(loop.contains(survivor))
        }
    }

    // MARK: - Half-edge consistency after collapse

    @Test("Live half-edges have consistent next/prev after collapse")
    func nextPrevConsistencyAfterCollapse() {
        var topo = makePyramid()
        let he = topo.halfEdges.first { $0.twin != nil }!
        topo.collapseEdge(he.id)
        for edge in liveHalfEdges(topo) {
            if let next = edge.next {
                #expect(topo.halfEdges[next.raw].prev == edge.id)
            }
            if let prev = edge.prev {
                #expect(topo.halfEdges[prev.raw].next == edge.id)
            }
        }
    }

    @Test("Live half-edges have symmetric twins after collapse")
    func twinSymmetryAfterCollapse() {
        var topo = makeTetrahedron()
        let he = topo.halfEdges.first { $0.twin != nil }!
        topo.collapseEdge(he.id)
        for edge in liveHalfEdges(topo) {
            if let twin = edge.twin {
                #expect(topo.halfEdges[twin.raw].twin == edge.id)
            }
        }
    }

    @Test("Live half-edges reference live faces after collapse")
    func halfEdgesReferenceLiveFaces() {
        var topo = makeTetrahedron()
        let he = topo.halfEdges.first { $0.twin != nil }!
        topo.collapseEdge(he.id)
        let liveFaceIDs = Set(liveFaces(topo).map(\.id))
        for edge in liveHalfEdges(topo) {
            if let faceID = edge.face {
                #expect(liveFaceIDs.contains(faceID))
            }
        }
    }

    @Test("Live vertices have outgoing edges that originate from them")
    func vertexEdgeOriginAfterCollapse() {
        var topo = makePyramid()
        let he = topo.halfEdges.first { $0.twin != nil }!
        topo.collapseEdge(he.id)
        for vertex in liveVertices(topo) {
            guard let edgeID = vertex.edge else {
                continue
            }
            #expect(topo.halfEdges[edgeID.raw].origin == vertex.id)
        }
    }

    // MARK: - Collapse preserves non-adjacent faces

    @Test("Collapse on triangle strip: non-adjacent face survives intact")
    func collapsePreservesNonAdjacentFace() {
        var topo = makeTriangleStrip()
        #expect(liveFaces(topo).count == 3)
        // Collapse an edge in the first triangle
        // Find half-edge in face 0 that has no twin (boundary of first triangle)
        let face0edges = topo.halfEdgeLoop(for: topo.faces[0].id)
        let boundaryHE = face0edges.first { topo.halfEdges[$0.raw].twin == nil }!
        topo.collapseEdge(boundaryHE)
        // Third triangle (face 2) should be completely unaffected
        let loop2 = topo.vertexLoop(for: topo.faces[2].id)
        #expect(loop2.count == 3)
    }

    // MARK: - Collapse same edge from twin direction

    @Test("Collapsing from twin gives opposite survivor")
    func collapseFromTwin() {
        let topo = makeTetrahedron()
        let he = topo.halfEdges.first { $0.twin != nil }!
        let twinID = he.twin!

        // Collapse original direction
        var topo1 = topo
        let survivor1 = topo1.collapseEdge(he.id)!

        // Collapse twin direction
        var topo2 = topo
        let survivor2 = topo2.collapseEdge(twinID)!

        // Survivors should be opposite vertices of the edge
        #expect(survivor1 != survivor2)
        #expect(survivor1 == he.origin)
        #expect(survivor2 == topo.halfEdges[twinID.raw].origin)

        // Both results should have same number of live faces/vertices
        #expect(liveFaces(topo1).count == liveFaces(topo2).count)
        #expect(liveVertices(topo1).count == liveVertices(topo2).count)
    }

    // MARK: - No self-loops in remaining topology

    @Test("No live half-edge has origin == dest after collapse")
    func noSelfLoopsAfterCollapse() {
        var topo = makeTetrahedron()
        let he = topo.halfEdges.first { $0.twin != nil }!
        topo.collapseEdge(he.id)
        for edge in liveHalfEdges(topo) {
            if let dest = topo.destViaNext(of: edge.id) {
                #expect(dest != edge.origin)
            }
        }
    }

    @Test("No self-loops after collapse on pyramid")
    func noSelfLoopsAfterCollapsePyramid() {
        var topo = makePyramid()
        let he = topo.halfEdges.first { $0.twin != nil }!
        topo.collapseEdge(he.id)
        for edge in liveHalfEdges(topo) {
            if let dest = topo.destViaNext(of: edge.id) {
                #expect(dest != edge.origin)
            }
        }
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

// MARK: - Manifold

@Suite("HalfEdgeTopology — Manifold")
struct HalfEdgeTopologyManifoldTests {
    @Test("Closed tetrahedron is manifold")
    func tetrahedronManifold() {
        let topo = HalfEdgeTopology(vertexCount: 4, faces: [
            .init(outer: [0, 1, 2]),
            .init(outer: [0, 3, 1]),
            .init(outer: [0, 2, 3]),
            .init(outer: [1, 3, 2])
        ])
        #expect(topo.isManifold)
    }

    @Test("Closed cube is manifold")
    func cubeManifold() {
        let topo = HalfEdgeTopology(vertexCount: 8, faces: [
            .init(outer: [0, 3, 2, 1]),
            .init(outer: [4, 5, 6, 7]),
            .init(outer: [0, 1, 5, 4]),
            .init(outer: [3, 7, 6, 2]),
            .init(outer: [1, 2, 6, 5]),
            .init(outer: [0, 4, 7, 3])
        ])
        #expect(topo.isManifold)
    }

    @Test("Single triangle is not manifold (boundary edges)")
    func singleTriangleNotManifold() {
        let topo = HalfEdgeTopology(vertexCount: 3, faces: [.init(outer: [0, 1, 2])])
        #expect(!topo.isManifold)
    }

    @Test("Quad is not manifold (boundary edges)")
    func quadNotManifold() {
        let topo = HalfEdgeTopology(vertexCount: 4, faces: [.init(outer: [0, 1, 2, 3])])
        #expect(!topo.isManifold)
    }

    @Test("Two adjacent triangles are not manifold (open boundary)")
    func twoTrianglesNotManifold() {
        let topo = HalfEdgeTopology(vertexCount: 4, faces: [
            .init(outer: [0, 1, 2]),
            .init(outer: [1, 3, 2])
        ])
        #expect(!topo.isManifold)
    }

    @Test("Platonic solids are manifold")
    func platonicSolidsManifold() {
        #expect(Mesh.tetrahedron(attributes: []).isManifold)
        #expect(Mesh.cube(attributes: []).isManifold)
        #expect(Mesh.octahedron(attributes: []).isManifold)
        #expect(Mesh.icosahedron(attributes: []).isManifold)
        #expect(Mesh.dodecahedron(attributes: []).isManifold)
    }

    @Test("Closed primitives are manifold")
    func closedPrimitivesManifold() {
        #expect(Mesh.box(attributes: []).isManifold)
        #expect(Mesh.sphere(attributes: []).isManifold)
        #expect(Mesh.icoSphere(attributes: []).isManifold)
        #expect(Mesh.torus(attributes: []).isManifold)
        #expect(Mesh.capsule(attributes: []).isManifold)
    }

    @Test("Capped primitives are manifold")
    func cappedPrimitivesManifold() {
        #expect(Mesh.cylinder(capped: true, attributes: []).isManifold)
        #expect(Mesh.hemisphere(capped: true, attributes: []).isManifold)
        #expect(Mesh.cone(capped: true, attributes: []).isManifold)
        #expect(Mesh.conicalFrustum(capped: true, attributes: []).isManifold)
        #expect(Mesh.rectangularFrustum(capped: true, attributes: []).isManifold)
    }

    @Test("Uncapped primitives are not manifold")
    func uncappedPrimitivesNotManifold() {
        #expect(!Mesh.cylinder(capped: false, attributes: []).isManifold)
        #expect(!Mesh.hemisphere(capped: false, attributes: []).isManifold)
        #expect(!Mesh.cone(capped: false, attributes: []).isManifold)
        #expect(!Mesh.conicalFrustum(capped: false, attributes: []).isManifold)
        #expect(!Mesh.rectangularFrustum(capped: false, attributes: []).isManifold)
    }

    @Test("Open surfaces are not manifold")
    func openSurfacesNotManifold() {
        #expect(!Mesh.triangle(attributes: []).isManifold)
        #expect(!Mesh.quad(attributes: []).isManifold)
        #expect(!Mesh.circle(attributes: []).isManifold)
    }

    @Test("Known non-manifold primitives (unwelded seams)")
    func knownNonManifoldPrimitives() {
        // cubeSphere (#62) and teapot (#63) have unwelded seam vertices
        #expect(!Mesh.cubeSphere(attributes: []).isManifold)
        #expect(!Mesh.teapot(attributes: []).isManifold)
    }
}
