import simd

public extension Mesh {
    /// A connected, coplanar group of faces.
    ///
    /// Charts are produced by region-growing across the half-edge topology:
    /// faces only merge when they share an edge *and* their planes are similar.
    /// This keeps disconnected coplanar pieces (e.g. two parallel walls) in
    /// separate charts.
    struct PlanarChart: Sendable, Equatable {
        /// Faces belonging to this chart, in discovery order.
        public var faces: [HalfEdgeTopology.FaceID]
        /// Average plane normal (area-weighted, unit length).
        public var normal: SIMD3<Float>
        /// In-plane unit vector forming the chart's local U axis.
        public var tangent: SIMD3<Float>
        /// In-plane unit vector forming the chart's local V axis (`normal × tangent`).
        public var bitangent: SIMD3<Float>
        /// World-space origin used when projecting positions into chart-local UV.
        public var planeOrigin: SIMD3<Float>
        /// Width and height (in world units) of the chart's 2D bounding rect in plane-local UV.
        public var worldExtent: SIMD2<Float>
        /// Minimum corner (in plane-local UV) — subtract this when projecting vertices.
        public var planeMin: SIMD2<Float>

        public init(
            faces: [HalfEdgeTopology.FaceID],
            normal: SIMD3<Float>,
            tangent: SIMD3<Float>,
            bitangent: SIMD3<Float>,
            planeOrigin: SIMD3<Float>,
            worldExtent: SIMD2<Float>,
            planeMin: SIMD2<Float>
        ) {
            self.faces = faces
            self.normal = normal
            self.tangent = tangent
            self.bitangent = bitangent
            self.planeOrigin = planeOrigin
            self.worldExtent = worldExtent
            self.planeMin = planeMin
        }
    }

    /// Partition the mesh into connected, coplanar charts via region growing.
    ///
    /// Two adjacent faces are merged into the same chart when:
    /// - the angle between their normals is `<= normalAngleTolerance` (radians), and
    /// - the perpendicular distance between their planes is `<= planeOffsetTolerance` (world units).
    ///
    /// - Parameters:
    ///   - normalAngleTolerance: Maximum angle (radians) between face normals for merging.
    ///     Default ≈ 5°.
    ///   - planeOffsetTolerance: Maximum signed-distance gap between face planes for merging.
    ///   - faces: Optional subset of faces to consider. Defaults to all faces.
    /// - Returns: Connected coplanar chart groups.
    func planarCharts(
        normalAngleTolerance: Float = 5 * .pi / 180,
        planeOffsetTolerance: Float = 0.01,
        faces: [HalfEdgeTopology.FaceID]? = nil
    ) -> [PlanarChart] {
        let candidateFaces = faces ?? topology.faces.map(\.id)
        guard !candidateFaces.isEmpty else { return [] }

        // Precompute per-face normal, area, and centroid for the candidate set.
        struct FaceInfo {
            var normal: SIMD3<Float>
            var area: Float
            var centroid: SIMD3<Float>
        }
        let candidateSet = Set(candidateFaces)
        var info: [HalfEdgeTopology.FaceID: FaceInfo] = [:]
        info.reserveCapacity(candidateFaces.count)
        for fid in candidateFaces {
            let pts = facePositions(fid)
            guard pts.count >= 3 else { continue }
            // Newell's-method normal weighted by polygon area.
            var n = SIMD3<Float>.zero
            for i in 0..<pts.count {
                let a = pts[i]
                let b = pts[(i + 1) % pts.count]
                n.x += (a.y - b.y) * (a.z + b.z)
                n.y += (a.z - b.z) * (a.x + b.x)
                n.z += (a.x - b.x) * (a.y + b.y)
            }
            let len = simd_length(n)
            let area = len * 0.5
            let unitN = len > 0 ? n / len : SIMD3<Float>(0, 0, 1)
            let centroid = pts.reduce(.zero, +) / Float(pts.count)
            info[fid] = FaceInfo(normal: unitN, area: area, centroid: centroid)
        }

        let cosTol = cos(normalAngleTolerance)

        var visited = Set<HalfEdgeTopology.FaceID>()
        var charts: [PlanarChart] = []

        for seed in candidateFaces {
            if visited.contains(seed) { continue }
            guard let seedInfo = info[seed] else {
                visited.insert(seed)
                continue
            }

            // BFS over neighbor faces (sharing an edge) whose plane matches the
            // running chart plane within tolerance.
            var chartFaces: [HalfEdgeTopology.FaceID] = []
            var weightedNormal = SIMD3<Float>.zero // area-weighted accumulator
            var weightedCentroid = SIMD3<Float>.zero
            var totalArea: Float = 0

            var queue: [HalfEdgeTopology.FaceID] = [seed]
            visited.insert(seed)

            while let current = queue.popLast() {
                guard let cInfo = info[current] else { continue }
                chartFaces.append(current)
                weightedNormal += cInfo.normal * cInfo.area
                weightedCentroid += cInfo.centroid * cInfo.area
                totalArea += cInfo.area

                // Current chart plane (running average).
                let avgLen = simd_length(weightedNormal)
                let avgNormal = avgLen > 0 ? weightedNormal / avgLen : seedInfo.normal
                let avgCentroid = totalArea > 0 ? weightedCentroid / totalArea : seedInfo.centroid

                for neighbor in topology.neighborFaces(of: current) {
                    if visited.contains(neighbor) { continue }
                    if !candidateSet.contains(neighbor) { continue }
                    guard let nInfo = info[neighbor] else {
                        visited.insert(neighbor)
                        continue
                    }
                    // Angle test
                    let dot = simd_dot(avgNormal, nInfo.normal)
                    if dot < cosTol { continue }
                    // Plane offset test: distance from neighbor centroid to chart plane
                    let offset = abs(simd_dot(nInfo.centroid - avgCentroid, avgNormal))
                    if offset > planeOffsetTolerance { continue }

                    visited.insert(neighbor)
                    queue.append(neighbor)
                }
            }

            // Build chart basis and 2D extent.
            let normal: SIMD3<Float> = {
                let len = simd_length(weightedNormal)
                return len > 0 ? weightedNormal / len : seedInfo.normal
            }()
            let origin = totalArea > 0 ? weightedCentroid / totalArea : seedInfo.centroid

            let (tangent, bitangent) = orthonormalBasis(for: normal)

            // Project chart's vertices into the (tangent, bitangent) basis and find 2D bbox.
            var seenVerts = Set<HalfEdgeTopology.VertexID>()
            var lo = SIMD2<Float>(.infinity, .infinity)
            var hi = SIMD2<Float>(-.infinity, -.infinity)
            for fid in chartFaces {
                for vid in topology.vertexLoop(for: fid) {
                    if !seenVerts.insert(vid).inserted { continue }
                    let p = positions[vid.raw] - origin
                    let uv = SIMD2<Float>(simd_dot(p, tangent), simd_dot(p, bitangent))
                    lo = simd_min(lo, uv)
                    hi = simd_max(hi, uv)
                }
            }
            // Guard against degenerate charts (single point / line) — clamp to zero.
            if !lo.x.isFinite || !lo.y.isFinite {
                lo = .zero
                hi = .zero
            }
            let extent = hi - lo

            charts.append(PlanarChart(
                faces: chartFaces,
                normal: normal,
                tangent: tangent,
                bitangent: bitangent,
                planeOrigin: origin,
                worldExtent: extent,
                planeMin: lo
            ))
        }

        return charts
    }
}

// MARK: - Internal helpers

/// Build a stable orthonormal (tangent, bitangent) pair perpendicular to `normal`.
///
/// Uses the "Building an Orthonormal Basis, Revisited" technique (Frisvad / Pixar)
/// for branch-light stability.
@inlinable
func orthonormalBasis(for normal: SIMD3<Float>) -> (tangent: SIMD3<Float>, bitangent: SIMD3<Float>) {
    let n = simd_normalize(normal)
    let sign: Float = n.z >= 0 ? 1 : -1
    let a = -1.0 / (sign + n.z)
    let b = n.x * n.y * a
    let tangent = SIMD3<Float>(1 + sign * n.x * n.x * a, sign * b, -sign * n.x)
    let bitangent = SIMD3<Float>(b, sign + n.y * n.y * a, -n.y)
    return (simd_normalize(tangent), simd_normalize(bitangent))
}
