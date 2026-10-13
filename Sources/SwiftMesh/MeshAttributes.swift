import simd
import SwiftMeshMikkTSpace

// MARK: - Normal Generation

public extension Mesh {
    /// Returns a new mesh with flat (per-face) normals assigned to every corner.
    func withFlatNormals() -> Mesh {
        var normals = [SIMD3<Float>](repeating: .zero, count: topology.halfEdges.count)

        for face in topology.faces {
            let normal = faceNormal(face.id)
            let heLoop = topology.halfEdgeLoop(for: face.id)
            for heID in heLoop {
                normals[heID.raw] = normal
            }
        }

        var result = self
        result.normals = normals
        return result
    }

    /// Returns a new mesh with smooth normals (face normals averaged at shared vertices).
    func withSmoothNormals() -> Mesh {
        // Accumulate face normals per vertex
        var vertexNormals = [SIMD3<Float>](repeating: .zero, count: topology.vertices.count)

        for face in topology.faces {
            let normal = faceNormal(face.id)
            let vertexIDs = topology.vertexLoop(for: face.id)
            for vid in vertexIDs {
                vertexNormals[vid.raw] += normal
            }
        }

        // Normalize
        for idx in vertexNormals.indices {
            let len = simd_length(vertexNormals[idx])
            if len > 0 {
                vertexNormals[idx] /= len
            }
        }

        // Write per-corner normals from the averaged vertex normals
        var normals = [SIMD3<Float>](repeating: .zero, count: topology.halfEdges.count)
        for he in topology.halfEdges {
            normals[he.id.raw] = vertexNormals[he.origin.raw]
        }

        var result = self
        result.normals = normals
        return result
    }

    /// The crease angle the shape generators use with `.smoothNormals`: 60 degrees.
    static let defaultCreaseAngle: Float = .pi / 3

    /// Returns a new mesh with smooth normals that keep hard edges.
    ///
    /// Each corner averages the normals of the faces around its vertex that are within `creaseAngle` (radians) of its
    /// own face, so faces that meet at a sharper angle keep separate normals.
    func withSmoothNormals(creaseAngle: Float) -> Mesh {
        let faceNormals = topology.faces.map { faceNormal($0.id) }
        var vertexFaces = [[Int]](repeating: [], count: topology.vertices.count)
        for halfEdge in topology.halfEdges {
            if let face = halfEdge.face {
                vertexFaces[halfEdge.origin.raw].append(face.raw)
            }
        }
        let threshold = cos(creaseAngle)
        var normals = [SIMD3<Float>](repeating: .zero, count: topology.halfEdges.count)
        for halfEdge in topology.halfEdges {
            guard let face = halfEdge.face else {
                continue
            }
            let ownNormal = faceNormals[face.raw]
            var sum = SIMD3<Float>.zero
            for other in vertexFaces[halfEdge.origin.raw] where simd_dot(ownNormal, faceNormals[other]) >= threshold {
                sum += faceNormals[other]
            }
            normals[halfEdge.id.raw] = simd_length(sum) > 0 ? simd_normalize(sum) : ownNormal
        }

        var result = self
        result.normals = normals
        return result
    }
}

// MARK: - UV Generation

public extension Mesh {
    /// Returns a new mesh with spherical UV coordinates computed from vertex positions.
    ///
    /// v runs from 0 at +Y to 1 at -Y. u runs once around the Y axis, counter-clockwise seen from above, so textures
    /// are not mirrored seen from outside. A face that crosses the seam gets u past 1 instead of wrapping, and a
    /// corner on the axis (a pole) takes the mean u of the face's other corners.
    func withSphericalUVs() -> Mesh {
        var uvs = [SIMD2<Float>](repeating: .zero, count: topology.halfEdges.count)

        for face in topology.faces {
            let corners = topology.halfEdgeLoop(for: face.id)
            var cornerUs: [Double?] = []
            for corner in corners {
                let position = SIMD3<Double>(positions[topology.halfEdges[corner.raw].origin.raw])
                let radius = simd_length(position)
                let cosTheta = radius > 0 ? max(-1.0, min(1.0, position.y / radius)) : 0.0
                uvs[corner.raw].y = Float(acos(cosTheta) / .pi)
                let onAxis = position.x * position.x + position.z * position.z <= 1e-12 * max(radius * radius, 1e-30)
                cornerUs.append(onAxis ? nil : 0.5 - atan2(position.z, position.x) / (2.0 * .pi))
            }
            let offAxis = cornerUs.compactMap(\.self)
            let wraps = (offAxis.max() ?? 0) - (offAxis.min() ?? 0) > 0.5
            let unwrapped = cornerUs.map { $0.map { wraps && $0 < 0.5 ? $0 + 1 : $0 } }
            let poleU = unwrapped.compactMap(\.self).reduce(0, +) / Double(max(1, offAxis.count))
            for (corner, u) in zip(corners, unwrapped) {
                uvs[corner.raw].x = Float(u ?? poleU)
            }
        }

        var result = self
        result.textureCoordinates = uvs
        return result
    }
}

/// The axis used for UV projection.
public enum ProjectionAxis: Sendable {
    case x, y, z
}

public extension Mesh {
    /// Returns a new mesh with planar UV coordinates projected along `axis`.
    ///
    /// The two axes perpendicular to `axis` are mapped to U and V,
    /// normalized to the mesh's bounding box.
    func withPlanarUVs(axis: ProjectionAxis = .z) -> Mesh {
        let (lo, hi) = bounds
        let size = hi - lo
        var uvs = [SIMD2<Float>](repeating: .zero, count: topology.halfEdges.count)

        for he in topology.halfEdges {
            let pos = positions[he.origin.raw]
            let u: Float
            let v: Float
            switch axis {
            case .x:
                u = size.z > 0 ? (pos.z - lo.z) / size.z : 0
                v = size.y > 0 ? (pos.y - lo.y) / size.y : 0

            case .y:
                u = size.x > 0 ? (pos.x - lo.x) / size.x : 0
                v = size.z > 0 ? (pos.z - lo.z) / size.z : 0

            case .z:
                u = size.x > 0 ? (pos.x - lo.x) / size.x : 0
                v = size.y > 0 ? (pos.y - lo.y) / size.y : 0
            }
            uvs[he.id.raw] = SIMD2<Float>(u, v)
        }

        var result = self
        result.textureCoordinates = uvs
        return result
    }

    /// Returns a new mesh with cylindrical UV coordinates unwrapped around `axis`.
    ///
    /// U is computed from the angle around the axis, V from the position
    /// along the axis normalized to the bounding box.
    func withCylindricalUVs(axis: ProjectionAxis = .y) -> Mesh {
        let (lo, hi) = bounds
        let size = hi - lo
        var uvs = [SIMD2<Float>](repeating: .zero, count: topology.halfEdges.count)

        for he in topology.halfEdges {
            let pos = positions[he.origin.raw]
            let u: Float
            let v: Float
            switch axis {
            case .x:
                let angle = atan2(Double(pos.z), Double(pos.y))
                u = Float(angle / (2 * .pi) + 0.5)
                v = size.x > 0 ? (pos.x - lo.x) / size.x : 0

            case .y:
                let angle = atan2(Double(pos.z), Double(pos.x))
                u = Float(angle / (2 * .pi) + 0.5)
                v = size.y > 0 ? (pos.y - lo.y) / size.y : 0

            case .z:
                let angle = atan2(Double(pos.y), Double(pos.x))
                u = Float(angle / (2 * .pi) + 0.5)
                v = size.z > 0 ? (pos.z - lo.z) / size.z : 0
            }
            uvs[he.id.raw] = SIMD2<Float>(u, v)
        }

        var result = self
        result.textureCoordinates = uvs
        return result
    }

    /// Returns a new mesh with box-projected UV coordinates.
    ///
    /// Each face is projected onto the plane most aligned with its normal
    /// (triplanar projection). UVs are normalized to the mesh's bounding box.
    func withBoxUVs() -> Mesh {
        let (lo, hi) = bounds
        let size = hi - lo
        var uvs = [SIMD2<Float>](repeating: .zero, count: topology.halfEdges.count)

        for face in topology.faces {
            let normal = faceNormal(face.id)
            let ax = abs(normal.x)
            let ay = abs(normal.y)
            let az = abs(normal.z)

            // Pick dominant axis
            let dominantAxis: ProjectionAxis
            if ax >= ay, ax >= az {
                dominantAxis = .x
            } else if ay >= az {
                dominantAxis = .y
            } else {
                dominantAxis = .z
            }

            let heLoop = topology.halfEdgeLoop(for: face.id)
            for heID in heLoop {
                let pos = positions[topology.halfEdges[heID.raw].origin.raw]
                let u: Float
                let v: Float
                switch dominantAxis {
                case .x:
                    u = size.z > 0 ? (pos.z - lo.z) / size.z : 0
                    v = size.y > 0 ? (pos.y - lo.y) / size.y : 0

                case .y:
                    u = size.x > 0 ? (pos.x - lo.x) / size.x : 0
                    v = size.z > 0 ? (pos.z - lo.z) / size.z : 0

                case .z:
                    u = size.x > 0 ? (pos.x - lo.x) / size.x : 0
                    v = size.y > 0 ? (pos.y - lo.y) / size.y : 0
                }
                uvs[heID.raw] = SIMD2<Float>(u, v)
            }
        }

        var result = self
        result.textureCoordinates = uvs
        return result
    }
}

// MARK: - Tangent Generation (MikkTSpace)

public extension Mesh {
    /// Returns a new mesh with tangents and bitangents computed via MikkTSpace.
    ///
    /// Requires normals and texture coordinates to be present.
    /// The mesh is triangulated internally for MikkTSpace processing.
    func withTangents() -> Mesh {
        guard let existingNormals = normals else {
            fatalError("withTangents() requires normals — call withFlatNormals() or withSmoothNormals() first")
        }
        guard let existingUVs = textureCoordinates else {
            fatalError("withTangents() requires texture coordinates — call withSphericalUVs() first")
        }

        // Triangulate to get flat triangle arrays for MikkTSpace
        let triangles = triangulate()

        // Build flat arrays indexed by triangle corner
        let cornerCount = triangles.count * 3
        var flatPositions = [SIMD3<Float>](repeating: .zero, count: cornerCount)
        var flatNormals = [SIMD3<Float>](repeating: .zero, count: cornerCount)
        var flatUVs = [SIMD2<Float>](repeating: .zero, count: cornerCount)
        var tangentsOut = [SIMD3<Float>](repeating: .zero, count: cornerCount)
        var bitangentsOut = [SIMD3<Float>](repeating: .zero, count: cornerCount)

        // We also need to map each corner back to a HalfEdgeID for writing results
        // For now, build a vertex→halfedge lookup per face
        var cornerToHE = [HalfEdgeTopology.HalfEdgeID?](repeating: nil, count: cornerCount)

        // Fill flat arrays in the same face order as triangulate().
        var cornerIdx = 0
        for face in topology.faces {
            for triangle in triangulatedCorners(of: face.id) {
                for heID in [triangle.0, triangle.1, triangle.2] {
                    flatPositions[cornerIdx] = positions[topology.halfEdges[heID.raw].origin.raw]
                    flatNormals[cornerIdx] = existingNormals[heID.raw]
                    flatUVs[cornerIdx] = existingUVs[heID.raw]
                    cornerToHE[cornerIdx] = heID
                    cornerIdx += 1
                }
            }
        }

        // Run MikkTSpace
        let faceCount = Int32(cornerIdx / 3)
        withUnsafeMutablePointer(to: &flatPositions) { posPtr in
            withUnsafeMutablePointer(to: &flatNormals) { normPtr in
                withUnsafeMutablePointer(to: &flatUVs) { uvPtr in
                    withUnsafeMutablePointer(to: &tangentsOut) { tanPtr in
                        withUnsafeMutablePointer(to: &bitangentsOut) { bitanPtr in
                            var userData = MikkUserData(
                                faceCount: faceCount,
                                positions: posPtr,
                                normals: normPtr,
                                uvs: uvPtr,
                                tangents: tanPtr,
                                bitangents: bitanPtr
                            )
                            withUnsafeMutablePointer(to: &userData) { udPtr in
                                var iface = SMikkTSpaceInterface()
                                iface.m_getNumFaces = { ctx in
                                    ctx!.pointee.m_pUserData!.assumingMemoryBound(to: MikkUserData.self).pointee.faceCount
                                }
                                iface.m_getNumVerticesOfFace = { _, _ in 3 }
                                iface.m_getPosition = { ctx, out, face, vert in
                                    let ud = ctx!.pointee.m_pUserData!.assumingMemoryBound(to: MikkUserData.self).pointee
                                    let pos = ud.positions.pointee[Int(face) * 3 + Int(vert)]
                                    out?[0] = pos.x; out?[1] = pos.y; out?[2] = pos.z
                                }
                                iface.m_getNormal = { ctx, out, face, vert in
                                    let ud = ctx!.pointee.m_pUserData!.assumingMemoryBound(to: MikkUserData.self).pointee
                                    let n = ud.normals.pointee[Int(face) * 3 + Int(vert)]
                                    out?[0] = n.x; out?[1] = n.y; out?[2] = n.z
                                }
                                iface.m_getTexCoord = { ctx, out, face, vert in
                                    let ud = ctx!.pointee.m_pUserData!.assumingMemoryBound(to: MikkUserData.self).pointee
                                    let uv = ud.uvs.pointee[Int(face) * 3 + Int(vert)]
                                    out?[0] = uv.x; out?[1] = uv.y
                                }
                                iface.m_setTSpace = { ctx, fvTangent, fvBiTangent, _, _, _, face, vert in
                                    let ud = ctx!.pointee.m_pUserData!.assumingMemoryBound(to: MikkUserData.self).pointee
                                    let idx = Int(face) * 3 + Int(vert)
                                    if let fvTangent {
                                        ud.tangents.pointee[idx] = SIMD3(fvTangent[0], fvTangent[1], fvTangent[2])
                                    }
                                    if let fvBiTangent {
                                        ud.bitangents.pointee[idx] = SIMD3(fvBiTangent[0], fvBiTangent[1], fvBiTangent[2])
                                    }
                                }

                                var ctx = SMikkTSpaceContext()
                                ctx.m_pUserData = UnsafeMutableRawPointer(udPtr)
                                withUnsafeMutablePointer(to: &iface) { ifacePtr in
                                    ctx.m_pInterface = ifacePtr
                                    let result = genTangSpaceDefault(&ctx)
                                    assert(result != 0, "MikkTSpace tangent generation failed")
                                }
                            }
                        }
                    }
                }
            }
        }

        // Write tangents back to per-corner arrays
        var resultTangents = [SIMD3<Float>](repeating: .zero, count: topology.halfEdges.count)
        var resultBitangents = [SIMD3<Float>](repeating: .zero, count: topology.halfEdges.count)
        var heCounts = [Int](repeating: 0, count: topology.halfEdges.count)

        for idx in 0..<cornerIdx {
            guard let heID = cornerToHE[idx] else {
                continue
            }
            resultTangents[heID.raw] += tangentsOut[idx]
            resultBitangents[heID.raw] += bitangentsOut[idx]
            heCounts[heID.raw] += 1
        }

        // Average and normalize
        for idx in resultTangents.indices where heCounts[idx] > 0 {
            let tLen = simd_length(resultTangents[idx])
            if tLen > 0 { resultTangents[idx] /= tLen }
            let bLen = simd_length(resultBitangents[idx])
            if bLen > 0 { resultBitangents[idx] /= bLen }
        }

        var result = self
        result.tangents = resultTangents
        result.bitangents = resultBitangents
        return result
    }
}

// MARK: - MikkTSpace interop

private struct MikkUserData {
    var faceCount: Int32
    var positions: UnsafeMutablePointer<[SIMD3<Float>]>
    var normals: UnsafeMutablePointer<[SIMD3<Float>]>
    var uvs: UnsafeMutablePointer<[SIMD2<Float>]>
    var tangents: UnsafeMutablePointer<[SIMD3<Float>]>
    var bitangents: UnsafeMutablePointer<[SIMD3<Float>]>
}
