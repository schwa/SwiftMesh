import BinPacking
import simd
@testable import SwiftMesh
import Testing

@Suite("PlanarCharts")
struct PlanarChartsTests {
    @Test("Single planar quad produces one chart")
    func singleQuad() {
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0)
        ], faces: [[0, 1, 2, 3]])

        let charts = mesh.planarCharts()
        #expect(charts.count == 1)
        let chart = charts[0]
        #expect(chart.faces.count == 1)
        #expect(abs(simd_dot(chart.normal, SIMD3<Float>(0, 0, 1))) > 0.999)
        // Extent should be ~1x1 in the chart's plane.
        #expect(abs(chart.worldExtent.x - 1) < 1e-4)
        #expect(abs(chart.worldExtent.y - 1) < 1e-4)
    }

    @Test("Box produces six charts (one per face)")
    func boxFaces() {
        let mesh = Mesh.box()
        let charts = mesh.planarCharts()
        #expect(charts.count == 6)
        // Each chart should cover exactly 1 face.
        for chart in charts {
            #expect(chart.faces.count == 1)
        }
    }

    @Test("Two disconnected coplanar quads stay in separate charts")
    func disconnectedCoplanar() {
        // Two unit quads on z=0 that don't share any vertices/edges.
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0),
            SIMD3(5, 0, 0), SIMD3(6, 0, 0), SIMD3(6, 1, 0), SIMD3(5, 1, 0)
        ], faces: [[0, 1, 2, 3], [4, 5, 6, 7]])

        let charts = mesh.planarCharts()
        #expect(charts.count == 2)
    }

    @Test("Two connected coplanar quads merge into one chart")
    func connectedCoplanar() {
        // Two quads sharing edge (1,2)-(2,3) (vertices 1,2 reused).
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0),
            SIMD3(2, 0, 0), SIMD3(2, 1, 0)
        ], faces: [[0, 1, 2, 3], [1, 4, 5, 2]])

        let charts = mesh.planarCharts()
        #expect(charts.count == 1)
        #expect(charts[0].faces.count == 2)
        // Combined extent is 2 (x) × 1 (y).
        #expect(abs(charts[0].worldExtent.x - 2) < 1e-4)
        #expect(abs(charts[0].worldExtent.y - 1) < 1e-4)
    }

    @Test("Angle tolerance separates adjacent non-coplanar faces")
    func angleSeparation() {
        // Quad in z=0 plane and quad in y=0 plane (90° dihedral) sharing the
        // edge (1, 0, 0) <-> (0, 0, 0). They should not merge.
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0),
            SIMD3(0, 0, 1), SIMD3(1, 0, 1)
        ], faces: [[0, 1, 2, 3], [0, 4, 5, 1]])

        let charts = mesh.planarCharts()
        #expect(charts.count == 2)
    }
}

@Suite("AtlasBaking")
struct AtlasBakingTests {
    @Test("Single quad bakes to UV-filling chart")
    func singleQuadAtlas() throws {
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0)
        ], faces: [[0, 1, 2, 3]])

        let (baked, layout) = try mesh.bakingPlanarAtlas(
            texelsPerMeter: 256,
            atlasSize: SIMD2<Int>(512, 512),
            padding: 0
        )

        #expect(layout.charts.count == 1)
        #expect(baked.textureCoordinates?.count == mesh.topology.halfEdges.count)
        // All UVs should be in [0, 1].
        for uv in baked.textureCoordinates ?? [] {
            #expect(uv.x >= 0 && uv.x <= 1)
            #expect(uv.y >= 0 && uv.y <= 1)
        }
    }

    @Test("Box bakes to six charts with valid UVs")
    func boxAtlas() throws {
        let mesh = Mesh.box(extents: [1, 1, 1])
        let (baked, layout) = try mesh.bakingPlanarAtlas(
            texelsPerMeter: 128,
            atlasSize: SIMD2<Int>(1_024, 1_024),
            padding: 2
        )

        #expect(layout.charts.count == 6)
        #expect(baked.textureCoordinates?.count == mesh.topology.halfEdges.count)
        for uv in baked.textureCoordinates ?? [] {
            #expect(uv.x >= 0 && uv.x <= 1)
            #expect(uv.y >= 0 && uv.y <= 1)
        }
        // Chart rects must lie within the atlas and not overlap.
        for chart in layout.charts {
            #expect(chart.atlasRect.minX >= 0)
            #expect(chart.atlasRect.minY >= 0)
            #expect(chart.atlasRect.maxX <= layout.atlasSize.x)
            #expect(chart.atlasRect.maxY <= layout.atlasSize.y)
        }
        for i in 0..<layout.charts.count {
            for j in (i + 1)..<layout.charts.count {
                #expect(!layout.charts[i].atlasRect.intersects(layout.charts[j].atlasRect))
            }
        }
    }

    @Test("Insufficient atlas throws")
    func insufficientAtlas() {
        let mesh = Mesh.box(extents: [10, 10, 10])
        // texelsPerMeter * extent vastly exceeds the tiny atlas.
        #expect(throws: AtlasBakingError.self) {
            _ = try mesh.bakingPlanarAtlas(
                texelsPerMeter: 1_000,
                atlasSize: SIMD2<Int>(64, 64),
                padding: 0
            )
        }
    }
}
