import MikkTSpace
import simd

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
}

// MARK: - UV Generation

public extension Mesh {
    /// Returns a new mesh with spherical UV coordinates computed from vertex positions.
    func withSphericalUVs() -> Mesh {
        var uvs = [SIMD2<Float>](repeating: .zero, count: topology.halfEdges.count)

        for he in topology.halfEdges {
            let pos = positions[he.origin.raw]
            let x = Double(pos.x)
            let y = Double(pos.y)
            let z = Double(pos.z)

            var u = atan2(z, x) / (2.0 * .pi) + 0.5
            u -= floor(u)

            let r = sqrt(x * x + y * y + z * z)
            let cosTheta = r > 0 ? max(-1.0, min(1.0, y / r)) : 0.0
            let v = acos(cosTheta) / .pi

            uvs[he.id.raw] = SIMD2<Float>(Float(u), Float(v))
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

        // Build per-face vertexID→heID maps
        var faceVertexToHE: [Int: [Int: HalfEdgeTopology.HalfEdgeID]] = [:]
        for face in topology.faces {
            let heLoop = topology.halfEdgeLoop(for: face.id)
            var mapping: [Int: HalfEdgeTopology.HalfEdgeID] = [:]
            for heID in heLoop {
                mapping[topology.halfEdges[heID.raw].origin.raw] = heID
            }
            faceVertexToHE[face.id.raw] = mapping
        }

        // Fill flat arrays
        // We need face info per triangle — rebuild from triangulate()
        // Since triangulate() walks faces in order, we can track which face each triangle came from
        var cornerIdx = 0
        for face in topology.faces {
            let verts = topology.vertexLoop(for: face.id)
            let faceTriangles: [(HalfEdgeTopology.VertexID, HalfEdgeTopology.VertexID, HalfEdgeTopology.VertexID)]
            if verts.count == 3 {
                faceTriangles = [(verts[0], verts[1], verts[2])]
            } else if verts.count < 3 {
                continue
            } else {
                faceTriangles = triangulateFace(vertexIDs: verts)
            }

            let mapping = faceVertexToHE[face.id.raw] ?? [:]
            for (v0, v1, v2) in faceTriangles {
                for vid in [v0, v1, v2] {
                    flatPositions[cornerIdx] = positions[vid.raw]
                    let heID = mapping[vid.raw]
                    if let heID {
                        flatNormals[cornerIdx] = existingNormals[heID.raw]
                        flatUVs[cornerIdx] = existingUVs[heID.raw]
                    }
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
