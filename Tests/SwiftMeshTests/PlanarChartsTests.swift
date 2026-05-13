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

    @Test("N connected coplanar quads merge into one chart", arguments: [2, 4, 10, 100])
    func nCoplanarQuadsMerge(n: Int) {
        // Build a strip of N unit quads along +X on the z=0 plane,
        // each sharing its left edge with the previous quad's right edge.
        // Vertices: 2 per column (top + bottom), N+1 columns → 2*(N+1) verts.
        var positions: [SIMD3<Float>] = []
        for i in 0...n {
            let x = Float(i)
            positions.append(SIMD3(x, 0, 0))
            positions.append(SIMD3(x, 1, 0))
        }
        var faces: [[Int]] = []
        for i in 0..<n {
            let a = i * 2        // bottom-left
            let b = i * 2 + 2    // bottom-right
            let c = i * 2 + 3    // top-right
            let d = i * 2 + 1    // top-left
            faces.append([a, b, c, d])
        }
        let mesh = Mesh(positions: positions, faces: faces)

        let charts = mesh.planarCharts()
        #expect(charts.count == 1)
        #expect(charts[0].faces.count == n)
        #expect(abs(charts[0].worldExtent.x - Float(n)) < 1e-3)
        #expect(abs(charts[0].worldExtent.y - 1) < 1e-3)
    }

    @Test("Triangulated polygon fan stays one chart")
    func triangulatedPolygonFan() {
        // Triangle fan around a center point on z=0. 8 outer ring vertices.
        let segments = 8
        var positions: [SIMD3<Float>] = [SIMD3(0, 0, 0)]
        for i in 0..<segments {
            let a = Float(i) / Float(segments) * 2 * .pi
            positions.append(SIMD3(cos(a), sin(a), 0))
        }
        var faces: [[Int]] = []
        for i in 0..<segments {
            let curr = 1 + i
            let next = 1 + (i + 1) % segments
            faces.append([0, curr, next])
        }
        let mesh = Mesh(positions: positions, faces: faces)

        let charts = mesh.planarCharts()
        #expect(charts.count == 1)
        #expect(charts[0].faces.count == segments)
        #expect(abs(simd_dot(charts[0].normal, SIMD3<Float>(0, 0, 1))) > 0.999)
    }

    @Test("Strip with accumulating tilt splits when running plane exceeds tolerance")
    func accumulatingTiltSplits() {
        // Build a strip of quads where each quad is tilted by ~2° relative to the
        // previous one (each pair-wise within the 5° default tolerance). After
        // several steps the running-average chart plane should diverge from a new
        // quad's normal by > 5° and the chart should split.
        let stepDegrees: Float = 2
        let stepRad = stepDegrees * .pi / 180
        let n = 10
        // Column endpoints: each successive column is rotated by stepRad about Y
        // around the previous column's bottom point. We model this as a hinge: each
        // quad lies on a plane rotated stepRad more than the previous.
        var positions: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(0, 1, 0)]
        var cursor = SIMD3<Float>(0, 0, 0)
        var dir = SIMD3<Float>(1, 0, 0)
        let rotAxis = SIMD3<Float>(0, 1, 0)
        for _ in 0..<n {
            // Rotate dir by stepRad about Y for each successive panel.
            let q = simd_quatf(angle: stepRad, axis: rotAxis)
            dir = simd_normalize(q.act(dir))
            cursor += dir
            positions.append(cursor)
            positions.append(cursor + SIMD3<Float>(0, 1, 0))
        }
        var faces: [[Int]] = []
        for i in 0..<n {
            let a = i * 2, b = i * 2 + 2, c = i * 2 + 3, d = i * 2 + 1
            faces.append([a, b, c, d])
        }
        let mesh = Mesh(positions: positions, faces: faces)

        // Each adjacent pair differs by 2° (within default 5° tolerance), but the
        // running-average plane will diverge from new quads after ~3-4 hinges.
        let charts = mesh.planarCharts()
        #expect(charts.count >= 2)
        // All faces should still be assigned exactly once.
        let assigned = charts.flatMap(\.faces)
        #expect(Set(assigned).count == n)
        #expect(assigned.count == n)
    }

    @Test("Disconnected coplanar triangle pairs stay separate")
    func disconnectedCoplanarTriangles() {
        // Two unit triangles on z=0, fully disjoint (no shared vertices).
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0),
            SIMD3(5, 0, 0), SIMD3(6, 0, 0), SIMD3(5, 1, 0)
        ], faces: [[0, 1, 2], [3, 4, 5]])

        let charts = mesh.planarCharts()
        #expect(charts.count == 2)
        for chart in charts {
            #expect(chart.faces.count == 1)
        }
    }

    @Test("planeOffsetTolerance keeps offset-but-parallel disconnected charts separate")
    func planeOffsetSeparatesParallelCharts() {
        // Two unit quads on parallel planes z=0 and z=0.05, no shared verts.
        // Default planeOffsetTolerance is 0.01 — they're disconnected anyway, so
        // they stay separate (this asserts the partitioner does not over-merge
        // disconnected coplanar geometry).
        let mesh = Mesh(positions: [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0),
            SIMD3(0, 0, 0.05), SIMD3(1, 0, 0.05), SIMD3(1, 1, 0.05), SIMD3(0, 1, 0.05)
        ], faces: [[0, 1, 2, 3], [4, 5, 6, 7]])

        let charts = mesh.planarCharts()
        #expect(charts.count == 2)
    }

    @Test("Faces filter restricts the partitioner to a subset")
    func facesFilter() {
        // Six-face box; restrict to a single face — should yield one chart with
        // exactly that face.
        let mesh = Mesh.box()
        let allFaces = mesh.topology.faces.map(\.id)
        let subset = [allFaces[2]]

        let charts = mesh.planarCharts(faces: subset)
        #expect(charts.count == 1)
        #expect(charts[0].faces == subset)

        // Pick two non-adjacent box faces (opposite sides): each becomes its own chart.
        // For a unit box, faces 0 and 1 are typically opposite. Just assert each
        // selected face stays in its own chart regardless of indexing.
        let twoFaces = [allFaces[0], allFaces[3]]
        let charts2 = mesh.planarCharts(faces: twoFaces)
        #expect(charts2.count == 2)
        let assigned2 = charts2.flatMap(\.faces)
        #expect(Set(assigned2) == Set(twoFaces))
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

    @Test("Insufficient atlas reports placed/total counts")
    func insufficientAtlasCounts() {
        let mesh = Mesh.box(extents: [10, 10, 10])
        do {
            _ = try mesh.bakingPlanarAtlas(
                texelsPerMeter: 1_000,
                atlasSize: SIMD2<Int>(64, 64),
                padding: 0
            )
            Issue.record("Expected insufficientAtlasSpace to throw")
        } catch let AtlasBakingError.insufficientAtlasSpace(placed, total) {
            // Box → 6 charts. Each chart is 10m × 1_000 texels/m = 10_000 px,
            // far larger than 64 px — none should fit.
            #expect(total == 6)
            #expect(placed >= 0 && placed < total)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Padding > 0 keeps chart rects non-intersecting on a box atlas")
    func paddingPreventsRectOverlap() throws {
        let mesh = Mesh.box(extents: [1, 1, 1])
        let padding = 4
        let (_, layout) = try mesh.bakingPlanarAtlas(
            texelsPerMeter: 128,
            atlasSize: SIMD2<Int>(1_024, 1_024),
            padding: padding
        )
        #expect(layout.charts.count == 6)
        // Pairwise: rects themselves should not intersect, and (the stronger
        // guarantee) each rect should be separated from every other by at least
        // `padding` pixels along one axis.
        for i in 0..<layout.charts.count {
            for j in (i + 1)..<layout.charts.count {
                let a = layout.charts[i].atlasRect
                let b = layout.charts[j].atlasRect
                #expect(!a.intersects(b))
                let gapX = max(a.minX - b.maxX, b.minX - a.maxX)
                let gapY = max(a.minY - b.maxY, b.minY - a.maxY)
                // At least one axis must show the padding gap.
                #expect(max(gapX, gapY) >= padding)
            }
        }
    }

    @Test("texelsPerMeter doubling roughly doubles chart pixel sizes")
    func texelsPerMeterScaling() throws {
        let mesh = Mesh.box(extents: [1, 1, 1])
        let (_, low) = try mesh.bakingPlanarAtlas(
            texelsPerMeter: 64,
            atlasSize: SIMD2<Int>(2_048, 2_048),
            padding: 0
        )
        let (_, high) = try mesh.bakingPlanarAtlas(
            texelsPerMeter: 128,
            atlasSize: SIMD2<Int>(2_048, 2_048),
            padding: 0
        )
        #expect(low.charts.count == high.charts.count)

        // Match by face set (placement order may differ).
        for lowChart in low.charts {
            guard let highChart = high.charts.first(where: { Set($0.faces) == Set(lowChart.faces) }) else {
                Issue.record("No matching high-res chart for faces \(lowChart.faces)")
                continue
            }
            // Compare areas: doubling texelsPerMeter quadruples pixel area.
            // Allow some slack for rotation + rounding.
            let lowArea = lowChart.atlasRect.size.x * lowChart.atlasRect.size.y
            let highArea = highChart.atlasRect.size.x * highChart.atlasRect.size.y
            let ratio = Double(highArea) / Double(lowArea)
            #expect(ratio > 3.5 && ratio < 4.5)
        }
    }

    @Test("Per-corner UV roundtrip recovers world position within a chart")
    func perCornerUVRoundtrip() throws {
        let mesh = Mesh.box(extents: [1, 1, 1])
        let atlasSize = SIMD2<Int>(1_024, 1_024)
        let (baked, layout) = try mesh.bakingPlanarAtlas(
            texelsPerMeter: 256,
            atlasSize: atlasSize,
            padding: 0
        )
        let uvs = try #require(baked.textureCoordinates)
        let atlasW = Float(atlasSize.x)
        let atlasH = Float(atlasSize.y)

        for placement in layout.charts {
            let rect = placement.atlasRect
            let rectW = Float(rect.size.x)
            let rectH = Float(rect.size.y)

            for fid in placement.faces {
                let loop = mesh.topology.halfEdgeLoop(for: fid)
                for he in loop {
                    let vid = mesh.topology.halfEdges[he.raw].origin
                    let worldP = mesh.positions[vid.raw]

                    // 1. Forward map: project world → chart-local UV (world units, 0…extent).
                    let p = worldP - placement.planeOrigin
                    let u = simd_dot(p, placement.planeU) - placement.planeMin.x
                    let v = simd_dot(p, placement.planeV) - placement.planeMin.y

                    // 2. Round-trip via stored UV: pixel → chart-local fraction → world position.
                    let uv = uvs[he.raw]
                    let px = uv.x * atlasW - Float(rect.origin.x)
                    let py = uv.y * atlasH - Float(rect.origin.y)
                    let chartU: Float
                    let chartV: Float
                    if placement.rotated {
                        // chart U → rect Y, chart V → rect X
                        chartV = px / rectW
                        chartU = py / rectH
                    } else {
                        chartU = px / rectW
                        chartV = py / rectH
                    }
                    let recoveredU = chartU * placement.worldExtent.x
                    let recoveredV = chartV * placement.worldExtent.y
                    let recoveredWorld = placement.planeOrigin
                        + (recoveredU + placement.planeMin.x) * placement.planeU
                        + (recoveredV + placement.planeMin.y) * placement.planeV

                    #expect(abs(recoveredU - u) < 1e-3)
                    #expect(abs(recoveredV - v) < 1e-3)
                    // World roundtrip is exact in the plane; tiny tolerance for float math.
                    let delta = simd_length(recoveredWorld - worldP)
                    #expect(delta < 1e-2, "world recovery off by \(delta) on face \(fid)")
                }
            }
        }
    }

    @Test("Shared-edge corners agree in UV across faces within a chart")
    func uvContinuityWithinChart() throws {
        // Strip of 4 connected coplanar quads → one chart; shared edge corners
        // should have identical UVs from both adjacent faces.
        var positions: [SIMD3<Float>] = []
        let n = 4
        for i in 0...n {
            let x = Float(i)
            positions.append(SIMD3(x, 0, 0))
            positions.append(SIMD3(x, 1, 0))
        }
        var faces: [[Int]] = []
        for i in 0..<n {
            let a = i * 2, b = i * 2 + 2, c = i * 2 + 3, d = i * 2 + 1
            faces.append([a, b, c, d])
        }
        let mesh = Mesh(positions: positions, faces: faces)

        let (baked, layout) = try mesh.bakingPlanarAtlas(
            texelsPerMeter: 128,
            atlasSize: SIMD2<Int>(512, 512),
            padding: 0
        )
        #expect(layout.charts.count == 1)
        let uvs = try #require(baked.textureCoordinates)

        // For every half-edge with a twin, both corners at the shared vertex
        // must produce the same UV (same chart, same vertex → same projection).
        for he in mesh.topology.halfEdges {
            guard let twinID = he.twin else { continue }
            let twin = mesh.topology.halfEdges[twinID.raw]
            // he.origin == dest(twin); compare he's UV at origin with the twin's
            // next corner (which sits at the same vertex as he.origin).
            // Simpler: compare the half-edge's UV with the next half-edge after
            // the twin (they share the vertex `he.origin`).
            guard let twinNextID = twin.next else { continue }
            let twinNext = mesh.topology.halfEdges[twinNextID.raw]
            // twinNext.origin should equal he.origin (the shared vertex).
            if twinNext.origin == he.origin {
                let a = uvs[he.id.raw]
                let b = uvs[twinNextID.raw]
                let delta = simd_length(a - b)
                #expect(delta < 1e-4, "UV mismatch at shared vertex: \(a) vs \(b)")
            }
        }
    }
}
