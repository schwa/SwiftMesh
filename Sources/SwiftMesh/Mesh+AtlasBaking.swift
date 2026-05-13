import BinPacking
import simd

/// Layout produced by ``Mesh/bakingPlanarAtlas(texelsPerMeter:atlasSize:padding:)``.
///
/// Describes the final atlas dimensions and, for each chart, the pixel rectangle it
/// occupies plus the chart-local plane basis needed to splat 3D positions back into
/// atlas pixels (e.g. from a ray-traced visibility pass).
public struct AtlasLayout: Sendable {
    public struct ChartPlacement: Sendable {
        /// Faces that compose this chart.
        public var faces: [HalfEdgeTopology.FaceID]
        /// Chart rectangle in atlas pixels (origin at minX/minY corner).
        public var atlasRect: Rect<Int>
        /// World-space origin of the chart's plane.
        public var planeOrigin: SIMD3<Float>
        /// Chart-local U axis (unit vector lying in the chart's plane).
        public var planeU: SIMD3<Float>
        /// Chart-local V axis (unit vector lying in the chart's plane).
        public var planeV: SIMD3<Float>
        /// World-space extent of the chart's 2D bounding rect (width along U, height along V).
        public var worldExtent: SIMD2<Float>
        /// Chart-local UV offset that maps a vertex into [0, worldExtent].
        ///
        /// Given a vertex `p`, its chart-local 2D coord is
        /// `SIMD2(dot(p - planeOrigin, planeU), dot(p - planeOrigin, planeV)) - planeMin`.
        public var planeMin: SIMD2<Float>
        /// Whether the chart was rotated 90° during packing (swap U/V when sampling).
        public var rotated: Bool

        public init(
            faces: [HalfEdgeTopology.FaceID],
            atlasRect: Rect<Int>,
            planeOrigin: SIMD3<Float>,
            planeU: SIMD3<Float>,
            planeV: SIMD3<Float>,
            worldExtent: SIMD2<Float>,
            planeMin: SIMD2<Float>,
            rotated: Bool
        ) {
            self.faces = faces
            self.atlasRect = atlasRect
            self.planeOrigin = planeOrigin
            self.planeU = planeU
            self.planeV = planeV
            self.worldExtent = worldExtent
            self.planeMin = planeMin
            self.rotated = rotated
        }
    }

    /// Atlas dimensions in pixels.
    public var atlasSize: SIMD2<Int>
    /// One entry per packed chart, in placement order.
    public var charts: [ChartPlacement]

    public init(atlasSize: SIMD2<Int>, charts: [ChartPlacement]) {
        self.atlasSize = atlasSize
        self.charts = charts
    }
}

/// Errors produced by atlas baking.
public enum AtlasBakingError: Error, Sendable {
    /// Not all charts fit into `atlasSize`. The included counts describe the failure.
    case insufficientAtlasSpace(placed: Int, total: Int)
}

public extension Mesh {
    /// Generate a planar UV atlas by partitioning into coplanar charts and bin-packing them.
    ///
    /// Each chart is projected into its own plane (using a chart-local tangent/bitangent
    /// basis), bin-packed into atlas pixel space, and the resulting per-corner UVs are
    /// written back to a new mesh. UVs are normalized to `[0, 1]^2`.
    ///
    /// - Parameters:
    ///   - texelsPerMeter: Scale factor from world meters to atlas pixels. Higher = more
    ///     atlas resolution per surface area.
    ///   - atlasSize: Target atlas dimensions in pixels.
    ///   - padding: Pixels of padding between charts (and at atlas borders) to prevent bleed.
    ///   - normalAngleTolerance: Forwarded to ``planarCharts(normalAngleTolerance:planeOffsetTolerance:faces:)``.
    ///   - planeOffsetTolerance: Forwarded to ``planarCharts(normalAngleTolerance:planeOffsetTolerance:faces:)``.
    /// - Returns: A new mesh with `textureCoordinates` populated, plus the chart layout.
    /// - Throws: ``AtlasBakingError/insufficientAtlasSpace(placed:total:)`` if any chart can't be placed.
    func bakingPlanarAtlas(
        texelsPerMeter: Float = 256,
        atlasSize: SIMD2<Int> = [2_048, 2_048],
        padding: Int = 2,
        normalAngleTolerance: Float = 5 * .pi / 180,
        planeOffsetTolerance: Float = 0.01
    ) throws -> (mesh: Mesh, atlas: AtlasLayout) {
        let charts = planarCharts(
            normalAngleTolerance: normalAngleTolerance,
            planeOffsetTolerance: planeOffsetTolerance
        )

        // Build pack items: convert each chart's world extent to pixel size.
        // Floor to at least 1px so degenerate charts still pack.
        var items: [PackingItem<Int, Int>] = []
        items.reserveCapacity(charts.count)
        for (idx, chart) in charts.enumerated() {
            let wPx = max(1, Int((chart.worldExtent.x * texelsPerMeter).rounded(.up)))
            let hPx = max(1, Int((chart.worldExtent.y * texelsPerMeter).rounded(.up)))
            items.append(PackingItem(id: idx, size: SIMD2<Int>(wPx, hPx)))
        }

        // Pack largest-area first for better packing efficiency.
        let sortedItems = items.sorted { $0.size.x * $0.size.y > $1.size.x * $1.size.y }

        var packer = MaxRectsPacker<Int>(
            binSize: atlasSize,
            allowRotation: true,
            padding: padding,
            heuristic: .bestShortSideFit
        )
        let result = packer.pack(sortedItems)

        if !result.allPlaced {
            throw AtlasBakingError.insufficientAtlasSpace(
                placed: result.placements.count,
                total: charts.count
            )
        }

        // Build placements indexed by chart index.
        var placementByChart: [Int: PackedRect<Int, Int>] = [:]
        placementByChart.reserveCapacity(result.placements.count)
        for p in result.placements {
            placementByChart[p.id] = p
        }

        // Allocate per-corner UVs.
        var uvs = [SIMD2<Float>](repeating: .zero, count: topology.halfEdges.count)
        let atlasW = Float(atlasSize.x)
        let atlasH = Float(atlasSize.y)

        var placements: [AtlasLayout.ChartPlacement] = []
        placements.reserveCapacity(charts.count)

        for (idx, chart) in charts.enumerated() {
            guard let placed = placementByChart[idx] else { continue }
            let rect = placed.rect

            // Pixel-space mapping. If the chart was rotated 90°, the chart's
            // local-U axis maps to the atlas's Y axis and vice versa.
            let rectW = Float(rect.size.x)
            let rectH = Float(rect.size.y)

            for fid in chart.faces {
                let loop = topology.halfEdgeLoop(for: fid)
                for he in loop {
                    let vid = topology.halfEdges[he.raw].origin
                    let p = positions[vid.raw] - chart.planeOrigin
                    let u = simd_dot(p, chart.tangent) - chart.planeMin.x
                    let v = simd_dot(p, chart.bitangent) - chart.planeMin.y

                    // Chart-local UV in [0, worldExtent] world units.
                    let chartU = chart.worldExtent.x > 0 ? u / chart.worldExtent.x : 0
                    let chartV = chart.worldExtent.y > 0 ? v / chart.worldExtent.y : 0

                    // Map chart-local UV to pixel rect (handling rotation).
                    let px: Float
                    let py: Float
                    if placed.rotated {
                        // Chart U → rect Y, chart V → rect X
                        px = Float(rect.origin.x) + chartV * rectW
                        py = Float(rect.origin.y) + chartU * rectH
                    } else {
                        px = Float(rect.origin.x) + chartU * rectW
                        py = Float(rect.origin.y) + chartV * rectH
                    }

                    uvs[he.raw] = SIMD2<Float>(px / atlasW, py / atlasH)
                }
            }

            placements.append(AtlasLayout.ChartPlacement(
                faces: chart.faces,
                atlasRect: rect,
                planeOrigin: chart.planeOrigin,
                planeU: chart.tangent,
                planeV: chart.bitangent,
                worldExtent: chart.worldExtent,
                planeMin: chart.planeMin,
                rotated: placed.rotated
            ))
        }

        var newMesh = self
        newMesh.textureCoordinates = uvs

        let layout = AtlasLayout(atlasSize: atlasSize, charts: placements)
        return (newMesh, layout)
    }
}
