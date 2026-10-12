// Ported from Manifold (https://github.com/elalish/manifold): src/impl.h, src/impl.cpp,
// src/properties.cpp, src/shared.h. Copyright 2021 The Manifold Authors.
// Licensed under the Apache License, Version 2.0; see NOTICE.

import simd

/// The triangle mesh the robust Boolean operates on (Manifold's `Manifold::Impl` subset).
///
/// Positions are `Double`. Every triangle has three consecutive half-edges, and every
/// half-edge is paired with exactly one opposite half-edge, so the mesh is a closed,
/// oriented 2-manifold.
package struct BooleanMesh: Sendable {
    package struct Halfedge: Sendable, Equatable {
        package var startVert: Int
        package var endVert: Int
        var pairedHalfedge: Int
        /// The `Mesh` corner (half-edge raw index) this corner came from, or -1 for new corners.
        /// Plays the role of Manifold's `propVert` for carrying attributes.
        var sourceCorner: Int
    }

    enum ConversionError: Error, Equatable {
        /// Some edge is not shared by exactly two triangles in opposite directions.
        case notManifold
        /// A position is NaN or infinite.
        case nonFinite
    }

    package var vertPos: [SIMD3<Double>] = []
    package var halfedges: [Halfedge] = []
    var faceNormal: [SIMD3<Double>] = []
    /// Angle-weighted pseudo-normals; used for symbolic perturbation.
    var vertNormal: [SIMD3<Double>] = []
    var boundsMin = SIMD3<Double>(repeating: .infinity)
    var boundsMax = SIMD3<Double>(repeating: -.infinity)
    /// Accumulated numerical error bound. Geometry closer than this may be treated as coincident.
    var epsilon: Double = 0

    var numVert: Int { vertPos.count }
    package var numTri: Int { halfedges.count / 3 }
    var numEdge: Int { halfedges.count / 2 }

    /// Manifold's `kPrecision`: the smallest relative precision tracked.
    static let relativePrecision = 1e-12

    static func nextHalfedge(_ edge: Int) -> Int {
        edge % 3 == 2 ? edge - 2 : edge + 1
    }
}

// MARK: - Construction

extension BooleanMesh {
    /// Builds from triangles over `positions`, pairing half-edges. Throws if not manifold.
    init(positions: [SIMD3<Double>], triangles: [SIMD3<Int>], sourceCorners: [SIMD3<Int>]? = nil) throws {
        guard positions.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else {
            throw ConversionError.nonFinite
        }
        vertPos = positions
        halfedges.reserveCapacity(triangles.count * 3)
        for (index, triangle) in triangles.enumerated() {
            for corner in 0..<3 {
                halfedges.append(Halfedge(
                    startVert: triangle[corner],
                    endVert: triangle[(corner + 1) % 3],
                    pairedHalfedge: -1,
                    sourceCorner: sourceCorners?[index][corner] ?? -1
                ))
            }
        }
        try pairHalfedges()
        guard isManifold else {
            throw ConversionError.notManifold
        }
        calculateBounds()
        setFaceAndVertNormals()
    }

    /// Pairs each forward half-edge with its unique reverse (Manifold's `CreateHalfedges`).
    private mutating func pairHalfedges() throws {
        // Key: undirected edge, then direction. A manifold edge has exactly one each way.
        var forward: [SIMD2<Int>: Int] = [:]
        var backward: [SIMD2<Int>: Int] = [:]
        forward.reserveCapacity(halfedges.count / 2)
        backward.reserveCapacity(halfedges.count / 2)
        for (index, edge) in halfedges.enumerated() {
            if edge.startVert == edge.endVert {
                throw ConversionError.notManifold
            }
            if edge.startVert < edge.endVert {
                guard forward.updateValue(index, forKey: [edge.startVert, edge.endVert]) == nil else {
                    throw ConversionError.notManifold
                }
            } else {
                guard backward.updateValue(index, forKey: [edge.endVert, edge.startVert]) == nil else {
                    throw ConversionError.notManifold
                }
            }
        }
        guard forward.count == backward.count else {
            throw ConversionError.notManifold
        }
        for (key, index) in forward {
            guard let pair = backward[key] else {
                throw ConversionError.notManifold
            }
            halfedges[index].pairedHalfedge = pair
            halfedges[pair].pairedHalfedge = index
        }
    }

    /// Manifold's `IsManifold` / `CheckHalfedges`: every half-edge paired with its reverse.
    var isManifold: Bool {
        guard halfedges.count.isMultiple(of: 3) else {
            return false
        }
        for (index, edge) in halfedges.enumerated() {
            let pair = edge.pairedHalfedge
            guard pair >= 0, pair < halfedges.count else {
                return false
            }
            let paired = halfedges[pair]
            guard paired.pairedHalfedge == index, edge.startVert != edge.endVert,
                  edge.startVert == paired.endVert, edge.endVert == paired.startVert else {
                return false
            }
        }
        return true
    }

    /// Manifold's `CalculateBBox`, which also sets epsilon from the bounding-box scale.
    mutating func calculateBounds() {
        boundsMin = SIMD3(repeating: .infinity)
        boundsMax = SIMD3(repeating: -.infinity)
        for position in vertPos {
            boundsMin = simd_min(boundsMin, position)
            boundsMax = simd_max(boundsMax, position)
        }
        // Inputs come from Float meshes, so precision is no better than Float's (as Manifold
        // does for float MeshGL).
        epsilon = max(Self.relativePrecision, Double(Float.ulpOfOne)) * scale
    }

    /// Manifold's `Box::Scale`: the largest absolute coordinate of the bounds.
    var scale: Double {
        guard boundsMin.x <= boundsMax.x else {
            return 0
        }
        let absMax = simd_max(simd_abs(boundsMin), simd_abs(boundsMax))
        return max(absMax.x, max(absMax.y, absMax.z))
    }

    /// Manifold's `SetFaceAndVertNormals` and `CalculateVertNormals`.
    mutating func setFaceAndVertNormals() {
        faceNormal = (0..<numTri).map { triangle in
            let v = vertPos[halfedges[3 * triangle].startVert]
            let normal = simd_cross(vertPos[halfedges[3 * triangle].endVert] - v, vertPos[halfedges[3 * triangle + 1].endVert] - v)
            return safeNormalize(normal)
        }
        var sums = [SIMD3<Double>](repeating: .zero, count: numVert)
        for edge in halfedges.indices {
            let triangle = edge / 3
            let start = halfedges[edge].startVert
            let end = halfedges[edge].endVert
            let previous = halfedges[Self.nextHalfedge(Self.nextHalfedge(edge))].startVert
            let currentEdge = simd_normalize(vertPos[end] - vertPos[start])
            let previousEdge = simd_normalize(vertPos[start] - vertPos[previous])
            // Degenerate triangles produce non-finite edges and are skipped.
            guard currentEdge.x.isFinite, previousEdge.x.isFinite else {
                continue
            }
            let dot = -simd_dot(previousEdge, currentEdge)
            let angle = dot >= 1 ? 0 : (dot <= -1 ? Double.pi : acos(dot))
            sums[start] += angle * faceNormal[triangle]
        }
        vertNormal = sums.map(safeNormalize)
    }
}

/// Manifold's `SafeNormalize`: zero for degenerate input instead of NaN.
func safeNormalize(_ vector: SIMD3<Double>) -> SIMD3<Double> {
    let normalized = simd_normalize(vector)
    return normalized.x.isFinite ? normalized : .zero
}

// MARK: - Mesh conversion

extension BooleanMesh {
    /// Converts a `Mesh`, triangulating n-gons and merging bit-identical positions so
    /// attribute seams (split vertices at the same place) don't break manifoldness.
    package init(mesh: Mesh) throws {
        let triangulated = mesh.triangulated()
        var mergedIndex: [SIMD3<Float>: Int] = [:]
        var vertexMap = [Int](repeating: -1, count: triangulated.positions.count)
        var positions: [SIMD3<Double>] = []
        for (index, position) in triangulated.positions.enumerated() {
            if let existing = mergedIndex[position] {
                vertexMap[index] = existing
            } else {
                mergedIndex[position] = positions.count
                vertexMap[index] = positions.count
                positions.append(SIMD3<Double>(position))
            }
        }
        var triangles: [SIMD3<Int>] = []
        var corners: [SIMD3<Int>] = []
        let topology = triangulated.topology
        for face in topology.faces where face.edge != nil {
            let loop = topology.halfEdgeLoop(for: face.id)
            guard loop.count == 3 else {
                continue
            }
            let vertices = loop.map { vertexMap[topology.halfEdges[$0.raw].origin.raw] }
            // Faces that collapse after merging are dropped, as Manifold does for degenerate input.
            guard Set(vertices).count == 3 else {
                continue
            }
            triangles.append(SIMD3(vertices[0], vertices[1], vertices[2]))
            corners.append(SIMD3(loop[0].raw, loop[1].raw, loop[2].raw))
        }
        try self.init(positions: positions, triangles: triangles, sourceCorners: corners)
        removeUnreferencedVertices()
    }

    /// Drops vertices no triangle uses and renumbers the rest.
    mutating func removeUnreferencedVertices() {
        var used = [Bool](repeating: false, count: numVert)
        for edge in halfedges {
            used[edge.startVert] = true
        }
        guard used.contains(false) else {
            return
        }
        var remap = [Int](repeating: -1, count: numVert)
        var kept: [SIMD3<Double>] = []
        var keptNormals: [SIMD3<Double>] = []
        for index in 0..<numVert where used[index] {
            remap[index] = kept.count
            kept.append(vertPos[index])
            keptNormals.append(vertNormal[index])
        }
        for index in halfedges.indices {
            halfedges[index].startVert = remap[halfedges[index].startVert]
            halfedges[index].endVert = remap[halfedges[index].endVert]
        }
        vertPos = kept
        vertNormal = keptNormals
    }

    /// A triangle `Mesh` with the same geometry. Attributes are not carried yet (#129).
    func toMesh() -> Mesh {
        let faces = (0..<numTri).map { triangle in
            (0..<3).map { halfedges[3 * triangle + $0].startVert }
        }
        return Mesh(positions: vertPos.map { SIMD3<Float>($0) }, faces: faces)
    }
}
