import Metal
import MetalKit
import ModelIO
import simd

// MARK: - Platonic Solids

public extension Mesh {
    /// A regular tetrahedron centered at the origin.
    static func tetrahedron(extents: SIMD3<Float> = [1, 1, 1], attributes: MeshAttributes = .default) -> Mesh {
        let positions: [SIMD3<Float>] = [
            SIMD3(1, 1, 1), SIMD3(-1, -1, 1), SIMD3(-1, 1, -1), SIMD3(1, -1, -1)
        ].map { simd_normalize($0) }
        var mesh = Mesh(positions: positions, faces: [
            [0, 1, 2], [0, 3, 1], [0, 2, 3], [1, 3, 2]
        ])
        mesh.fitToExtents(extents)

        if attributes.contains(.textureCoordinates) {
            let triUVs: [SIMD2<Float>] = [
                SIMD2(0, 0), SIMD2(1, 0), SIMD2(0.5, 1)
            ]
            var uvs = [SIMD2<Float>](repeating: .zero, count: mesh.topology.halfEdges.count)
            for face in mesh.topology.faces {
                let heLoop = mesh.topology.halfEdgeLoop(for: face.id)
                for (i, he) in heLoop.enumerated() {
                    uvs[he.raw] = triUVs[i]
                }
            }
            mesh.textureCoordinates = uvs
        }

        mesh.applyAttributes(attributes)
        return mesh
    }

    /// A regular cube centered at the origin.
    static func cube(extents: SIMD3<Float> = [1, 1, 1], attributes: MeshAttributes = .default) -> Mesh {
        let positions: [SIMD3<Float>] = [
            SIMD3(-1, -1, -1), SIMD3(1, -1, -1), SIMD3(1, 1, -1), SIMD3(-1, 1, -1),
            SIMD3(-1, -1, 1), SIMD3(1, -1, 1), SIMD3(1, 1, 1), SIMD3(-1, 1, 1)
        ]
        var mesh = Mesh(positions: positions, faces: [
            [0, 3, 2, 1], [4, 5, 6, 7],
            [0, 1, 5, 4], [3, 7, 6, 2],
            [1, 2, 6, 5], [0, 4, 7, 3]
        ])
        mesh.fitToExtents(extents)

        if attributes.contains(.textureCoordinates) {
            // Each quad face maps to the full [0,1]×[0,1] square.
            let quadUVs: [SIMD2<Float>] = [
                SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)
            ]
            var uvs = [SIMD2<Float>](repeating: .zero, count: mesh.topology.halfEdges.count)
            for face in mesh.topology.faces {
                let heLoop = mesh.topology.halfEdgeLoop(for: face.id)
                for (i, he) in heLoop.enumerated() {
                    uvs[he.raw] = quadUVs[i]
                }
            }
            mesh.textureCoordinates = uvs
        }

        mesh.applyAttributes(attributes)
        return mesh
    }

    /// A regular octahedron centered at the origin.
    static func octahedron(extents: SIMD3<Float> = [1, 1, 1], attributes: MeshAttributes = .default) -> Mesh {
        let positions: [SIMD3<Float>] = [
            SIMD3(1, 0, 0), SIMD3(-1, 0, 0), SIMD3(0, 1, 0),
            SIMD3(0, -1, 0), SIMD3(0, 0, 1), SIMD3(0, 0, -1)
        ]
        var mesh = Mesh(positions: positions, faces: [
            [0, 2, 4], [0, 4, 3], [0, 3, 5], [0, 5, 2],
            [1, 2, 5], [1, 5, 3], [1, 3, 4], [1, 4, 2]
        ])
        mesh.fitToExtents(extents)

        if attributes.contains(.textureCoordinates) {
            let triUVs: [SIMD2<Float>] = [
                SIMD2(0, 0), SIMD2(1, 0), SIMD2(0.5, 1)
            ]
            var uvs = [SIMD2<Float>](repeating: .zero, count: mesh.topology.halfEdges.count)
            for face in mesh.topology.faces {
                let heLoop = mesh.topology.halfEdgeLoop(for: face.id)
                for (i, he) in heLoop.enumerated() {
                    uvs[he.raw] = triUVs[i]
                }
            }
            mesh.textureCoordinates = uvs
        }

        mesh.applyAttributes(attributes)
        return mesh
    }

    /// A regular icosahedron centered at the origin.
    static func icosahedron(extents: SIMD3<Float> = [1, 1, 1], attributes: MeshAttributes = .default) -> Mesh {
        let phi: Float = (1.0 + sqrt(5.0)) / 2.0
        let positions: [SIMD3<Float>] = [
            SIMD3(-1, phi, 0), SIMD3(1, phi, 0), SIMD3(-1, -phi, 0), SIMD3(1, -phi, 0),
            SIMD3(0, -1, phi), SIMD3(0, 1, phi), SIMD3(0, -1, -phi), SIMD3(0, 1, -phi),
            SIMD3(phi, 0, -1), SIMD3(phi, 0, 1), SIMD3(-phi, 0, -1), SIMD3(-phi, 0, 1)
        ].map { simd_normalize($0) }
        var mesh = Mesh(positions: positions, faces: [
            [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
            [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
            [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
            [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]
        ])
        mesh.fitToExtents(extents)

        if attributes.contains(.textureCoordinates) {
            let triUVs: [SIMD2<Float>] = [
                SIMD2(0, 0), SIMD2(1, 0), SIMD2(0.5, 1)
            ]
            var uvs = [SIMD2<Float>](repeating: .zero, count: mesh.topology.halfEdges.count)
            for face in mesh.topology.faces {
                let heLoop = mesh.topology.halfEdgeLoop(for: face.id)
                for (i, he) in heLoop.enumerated() {
                    uvs[he.raw] = triUVs[i]
                }
            }
            mesh.textureCoordinates = uvs
        }

        mesh.applyAttributes(attributes)
        return mesh
    }

    /// A regular dodecahedron centered at the origin.
    static func dodecahedron(extents: SIMD3<Float> = [1, 1, 1], attributes: MeshAttributes = .default) -> Mesh {
        let phi: Float = (1.0 + sqrt(5.0)) / 2.0
        let invPhi: Float = 1.0 / phi
        let positions: [SIMD3<Float>] = [
            SIMD3(1, 1, 1), SIMD3(1, 1, -1), SIMD3(1, -1, 1), SIMD3(1, -1, -1),
            SIMD3(-1, 1, 1), SIMD3(-1, 1, -1), SIMD3(-1, -1, 1), SIMD3(-1, -1, -1),
            SIMD3(0, invPhi, phi), SIMD3(0, invPhi, -phi),
            SIMD3(0, -invPhi, phi), SIMD3(0, -invPhi, -phi),
            SIMD3(invPhi, phi, 0), SIMD3(invPhi, -phi, 0),
            SIMD3(-invPhi, phi, 0), SIMD3(-invPhi, -phi, 0),
            SIMD3(phi, 0, invPhi), SIMD3(phi, 0, -invPhi),
            SIMD3(-phi, 0, invPhi), SIMD3(-phi, 0, -invPhi)
        ].map { simd_normalize($0) }
        var mesh = Mesh(positions: positions, faces: [
            [0, 8, 10, 2, 16], [0, 16, 17, 1, 12], [0, 12, 14, 4, 8],
            [1, 17, 3, 11, 9], [1, 9, 5, 14, 12], [2, 10, 6, 15, 13],
            [2, 13, 3, 17, 16], [3, 13, 15, 7, 11], [4, 14, 5, 19, 18],
            [4, 18, 6, 10, 8], [5, 9, 11, 7, 19], [6, 18, 19, 7, 15]
        ])
        mesh.fitToExtents(extents)

        if attributes.contains(.textureCoordinates) {
            // Regular pentagon UVs: vertices equally spaced on a unit circle,
            // centered at (0.5, 0.5) and scaled to fit.
            var pentUVs = [SIMD2<Float>]()
            for i in 0..<5 {
                let angle = Float.pi / 2 + 2 * Float.pi * Float(i) / 5
                pentUVs.append(SIMD2(0.5 + 0.5 * cos(angle), 0.5 - 0.5 * sin(angle)))
            }
            var uvs = [SIMD2<Float>](repeating: .zero, count: mesh.topology.halfEdges.count)
            for face in mesh.topology.faces {
                let heLoop = mesh.topology.halfEdgeLoop(for: face.id)
                for (i, he) in heLoop.enumerated() {
                    uvs[he.raw] = pentUVs[i]
                }
            }
            mesh.textureCoordinates = uvs
        }

        mesh.applyAttributes(attributes)
        return mesh
    }
}

// MARK: - Simple Primitives

public extension Mesh {
    /// A single triangle in the XY plane, centered at the origin.
    static func triangle(extents: SIMD2<Float> = [1, 1], attributes: MeshAttributes = .default) -> Mesh {
        // Unit equilateral-ish triangle fitting in -0.5...0.5
        var mesh = Mesh(positions: [
            SIMD3(0, 0.5, 0), SIMD3(-0.5, -0.5, 0), SIMD3(0.5, -0.5, 0)
        ], faces: [[0, 1, 2]])
        mesh.fitToExtents(SIMD3(extents.x, extents.y, 0))

        if attributes.contains(.textureCoordinates) {
            let heLoop = mesh.topology.halfEdgeLoop(for: HalfEdgeTopology.FaceID(raw: 0))
            var uvs = [SIMD2<Float>](repeating: .zero, count: mesh.topology.halfEdges.count)
            uvs[heLoop[0].raw] = SIMD2(0.5, 0) // top vertex
            uvs[heLoop[1].raw] = SIMD2(0, 1)   // bottom-left
            uvs[heLoop[2].raw] = SIMD2(1, 1)   // bottom-right
            mesh.textureCoordinates = uvs
        }

        mesh.applyAttributes(attributes)
        return mesh
    }

    /// A quad in the XY plane, centered at the origin.
    static func quad(extents: SIMD2<Float> = [1, 1], attributes: MeshAttributes = .default) -> Mesh {
        let hw = extents.x / 2
        let hh = extents.y / 2
        var mesh = Mesh(positions: [
            SIMD3(-hw, -hh, 0), SIMD3(hw, -hh, 0),
            SIMD3(hw, hh, 0), SIMD3(-hw, hh, 0)
        ], faces: [[0, 1, 2, 3]])

        if attributes.contains(.textureCoordinates) {
            let heLoop = mesh.topology.halfEdgeLoop(for: HalfEdgeTopology.FaceID(raw: 0))
            var uvs = [SIMD2<Float>](repeating: .zero, count: mesh.topology.halfEdges.count)
            uvs[heLoop[0].raw] = SIMD2(0, 0)
            uvs[heLoop[1].raw] = SIMD2(1, 0)
            uvs[heLoop[2].raw] = SIMD2(1, 1)
            uvs[heLoop[3].raw] = SIMD2(0, 1)
            mesh.textureCoordinates = uvs
        }

        mesh.applyAttributes(attributes)
        return mesh
    }

    /// A box centered at the origin with quad faces.
    static func box(extents: SIMD3<Float> = [1, 1, 1], attributes: MeshAttributes = .default) -> Mesh {
        let h = extents / 2
        let positions: [SIMD3<Float>] = [
            SIMD3(-h.x, -h.y, h.z), SIMD3(h.x, -h.y, h.z),
            SIMD3(h.x, h.y, h.z), SIMD3(-h.x, h.y, h.z),
            SIMD3(-h.x, -h.y, -h.z), SIMD3(h.x, -h.y, -h.z),
            SIMD3(h.x, h.y, -h.z), SIMD3(-h.x, h.y, -h.z)
        ]
        var mesh = Mesh(positions: positions, faces: [
            [0, 1, 2, 3],     // front
            [5, 4, 7, 6],     // back
            [4, 0, 3, 7],     // left
            [1, 5, 6, 2],     // right
            [3, 2, 6, 7],     // top
            [4, 5, 1, 0]      // bottom
        ])

        if attributes.contains(.textureCoordinates) {
            let quadUVs: [SIMD2<Float>] = [
                SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)
            ]
            var uvs = [SIMD2<Float>](repeating: .zero, count: mesh.topology.halfEdges.count)
            for face in mesh.topology.faces {
                let heLoop = mesh.topology.halfEdgeLoop(for: face.id)
                for (i, he) in heLoop.enumerated() {
                    uvs[he.raw] = quadUVs[i]
                }
            }
            mesh.textureCoordinates = uvs
        }

        mesh.applyAttributes(attributes)
        return mesh
    }
    /// A circle (flat disc) in the XY plane, centered at the origin.
    ///
    /// Built as a single n-gon fan. `segments` controls the number of edges.
    static func circle(extents: SIMD2<Float> = [1, 1], segments: Int = 32, attributes: MeshAttributes = .default) -> Mesh {
        let hw = extents.x / 2
        let hh = extents.y / 2
        var positions: [SIMD3<Float>] = []

        // Center vertex
        positions.append(SIMD3(0, 0, 0))

        // Rim vertices
        for seg in 0..<segments {
            let angle = 2 * Float.pi * Float(seg) / Float(segments)
            positions.append(SIMD3(hw * cos(angle), hh * sin(angle), 0))
        }

        // Triangle fan faces
        var faces: [[Int]] = []
        for seg in 0..<segments {
            let nextSeg = (seg + 1) % segments
            faces.append([0, 1 + seg, 1 + nextSeg])
        }

        var mesh = Mesh(positions: positions, faces: faces)

        if attributes.contains(.textureCoordinates) {
            var uvs = [SIMD2<Float>](repeating: .zero, count: mesh.topology.halfEdges.count)
            for seg in 0..<segments {
                let faceID = HalfEdgeTopology.FaceID(raw: seg)
                let heLoop = mesh.topology.halfEdgeLoop(for: faceID)
                // Center
                uvs[heLoop[0].raw] = SIMD2(0.5, 0.5)
                // Current rim vertex
                let angle0 = 2 * Float.pi * Float(seg) / Float(segments)
                uvs[heLoop[1].raw] = SIMD2(0.5 + 0.5 * cos(angle0), 0.5 + 0.5 * sin(angle0))
                // Next rim vertex
                let angle1 = 2 * Float.pi * Float(seg + 1) / Float(segments)
                uvs[heLoop[2].raw] = SIMD2(0.5 + 0.5 * cos(angle1), 0.5 + 0.5 * sin(angle1))
            }
            mesh.textureCoordinates = uvs
        }

        mesh.applyAttributes(attributes)
        return mesh
    }
}

// MARK: - Parametric Surfaces

public extension Mesh {
    /// A UV sphere (or ellipsoid) with quad faces (and triangle caps at the poles).
    static func sphere(extents: SIMD3<Float> = [1, 1, 1], latitudeSegments: Int = 16, longitudeSegments: Int = 32, attributes: MeshAttributes = .default) -> Mesh {
        let radii = extents / 2
        var positions: [SIMD3<Float>] = []
        var faces: [[Int]] = []

        // Top pole
        positions.append(SIMD3(0, radii.y, 0))

        // Latitude rings (excluding poles)
        for lat in 1..<latitudeSegments {
            let theta = Float.pi * Float(lat) / Float(latitudeSegments)
            let sinTheta = sin(theta)
            let cosTheta = cos(theta)
            for lon in 0..<longitudeSegments {
                let phi = 2 * Float.pi * Float(lon) / Float(longitudeSegments)
                positions.append(SIMD3(radii.x * sinTheta * cos(phi), radii.y * cosTheta, radii.z * sinTheta * sin(phi)))
            }
        }

        // Bottom pole
        let bottomPole = positions.count
        positions.append(SIMD3(0, -radii.y, 0))

        // Top cap triangles
        for lon in 0..<longitudeSegments {
            let nextLon = (lon + 1) % longitudeSegments
            faces.append([0, 1 + lon, 1 + nextLon])
        }

        // Quad strips between latitude rings
        for lat in 0..<(latitudeSegments - 2) {
            let ringStart = 1 + lat * longitudeSegments
            let nextRingStart = ringStart + longitudeSegments
            for lon in 0..<longitudeSegments {
                let nextLon = (lon + 1) % longitudeSegments
                faces.append([
                    ringStart + lon,
                    nextRingStart + lon,
                    nextRingStart + nextLon,
                    ringStart + nextLon
                ])
            }
        }

        // Bottom cap triangles
        let lastRingStart = 1 + (latitudeSegments - 2) * longitudeSegments
        for lon in 0..<longitudeSegments {
            let nextLon = (lon + 1) % longitudeSegments
            faces.append([lastRingStart + lon, bottomPole, lastRingStart + nextLon])
        }

        var mesh = Mesh(positions: positions, faces: faces)

        if attributes.contains(.textureCoordinates) {
            // Assign per-corner UVs from parametric coordinates.
            // For each half-edge we know which face it belongs to and which vertex it
            // originates from, so we can recover the (lat, lon) indices and compute
            // proper seam-aware UVs.
            //
            // Vertex index layout:
            //   0              = top pole
            //   1 ..< 1+N*(L-1) = ring vertices  (ring r, slot s -> index 1 + r*N + s)
            //   bottomPole     = bottom pole
            // where N = longitudeSegments, L = latitudeSegments.
            //
            // Face order (mirrors construction above):
            //   [0, N)                          top cap triangles  (lon 0..<N)
            //   [N, N + (L-2)*N)                quad strip faces   (lat 0..<L-2, lon 0..<N)
            //   [N + (L-2)*N, N + (L-2)*N + N)  bottom cap triangles (lon 0..<N)

            let N = longitudeSegments
            let L = latitudeSegments

            var uvs = [SIMD2<Float>](repeating: .zero, count: mesh.topology.halfEdges.count)

            // Helper: UV for a ring vertex at (latRing 1-based, lonSlot) within a face
            // whose longitudinal column is `faceLon`.
            // `latRing` is 1..L-1 for ring vertices, 0 for top pole, L for bottom pole.
            func uv(latRing: Int, lonSlot: Int, faceLon: Int) -> SIMD2<Float> {
                let v = Float(latRing) / Float(L)
                // For the last column (faceLon == N-1), the "next" longitude wraps to
                // slot 0, which should map to u=1.0, not u=0.0.
                let effectiveLon: Float
                if lonSlot == 0, faceLon == N - 1 {
                    effectiveLon = Float(N)
                } else {
                    effectiveLon = Float(lonSlot)
                }
                let u = effectiveLon / Float(N)
                return SIMD2<Float>(u, v)
            }

            var faceIndex = 0

            // Top cap triangles: face vertices are [pole, ring0+lon, ring0+nextLon]
            for lon in 0..<N {
                let nextLon = (lon + 1) % N
                let heLoop = mesh.topology.halfEdgeLoop(for: HalfEdgeTopology.FaceID(raw: faceIndex))
                // 3 half-edges: pole, ring0+lon, ring0+nextLon
                // Pole gets u centered on this face's longitude column
                let polU = (Float(lon) + 0.5) / Float(N)
                uvs[heLoop[0].raw] = SIMD2<Float>(polU, 0)            // top pole
                uvs[heLoop[1].raw] = uv(latRing: 1, lonSlot: lon, faceLon: lon)
                uvs[heLoop[2].raw] = uv(latRing: 1, lonSlot: nextLon, faceLon: lon)
                faceIndex += 1
            }

            // Quad strip faces
            for lat in 0..<(L - 2) {
                for lon in 0..<N {
                    let nextLon = (lon + 1) % N
                    let heLoop = mesh.topology.halfEdgeLoop(for: HalfEdgeTopology.FaceID(raw: faceIndex))
                    // 4 half-edges: ringStart+lon, nextRingStart+lon, nextRingStart+nextLon, ringStart+nextLon
                    let latRing = lat + 1
                    uvs[heLoop[0].raw] = uv(latRing: latRing, lonSlot: lon, faceLon: lon)
                    uvs[heLoop[1].raw] = uv(latRing: latRing + 1, lonSlot: lon, faceLon: lon)
                    uvs[heLoop[2].raw] = uv(latRing: latRing + 1, lonSlot: nextLon, faceLon: lon)
                    uvs[heLoop[3].raw] = uv(latRing: latRing, lonSlot: nextLon, faceLon: lon)
                    faceIndex += 1
                }
            }

            // Bottom cap triangles: face vertices are [lastRing+lon, bottomPole, lastRing+nextLon]
            for lon in 0..<N {
                let nextLon = (lon + 1) % N
                let heLoop = mesh.topology.halfEdgeLoop(for: HalfEdgeTopology.FaceID(raw: faceIndex))
                // 3 half-edges: lastRing+lon, bottomPole, lastRing+nextLon
                let polU = (Float(lon) + 0.5) / Float(N)
                uvs[heLoop[0].raw] = uv(latRing: L - 1, lonSlot: lon, faceLon: lon)
                uvs[heLoop[1].raw] = SIMD2<Float>(polU, 1)            // bottom pole
                uvs[heLoop[2].raw] = uv(latRing: L - 1, lonSlot: nextLon, faceLon: lon)
                faceIndex += 1
            }

            mesh.textureCoordinates = uvs
        } // end .textureCoordinates

        mesh.applyAttributes(attributes)
        return mesh
    }

    /// An icosphere built by subdividing an icosahedron and projecting vertices
    /// onto a sphere. Produces a more uniform triangle distribution than a UV sphere.
    ///
    /// - Parameter subdivisions: Number of subdivision iterations (0 = icosahedron, each step ×4 faces).
    static func icoSphere(extents: SIMD3<Float> = [1, 1, 1], subdivisions: Int = 3, attributes: MeshAttributes = .default) -> Mesh {
        // Start from icosahedron vertices on the unit sphere
        let phi: Float = (1.0 + sqrt(5.0)) / 2.0
        var positions: [SIMD3<Float>] = [
            SIMD3(-1, phi, 0), SIMD3(1, phi, 0), SIMD3(-1, -phi, 0), SIMD3(1, -phi, 0),
            SIMD3(0, -1, phi), SIMD3(0, 1, phi), SIMD3(0, -1, -phi), SIMD3(0, 1, -phi),
            SIMD3(phi, 0, -1), SIMD3(phi, 0, 1), SIMD3(-phi, 0, -1), SIMD3(-phi, 0, 1)
        ].map { simd_normalize($0) }

        var triangles: [[Int]] = [
            [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
            [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
            [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
            [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]
        ]

        // Subdivide
        var vertexCount = positions.count
        for _ in 0..<subdivisions {
            var midpointCache: [Int64: Int] = [:]
            var newTriangles: [[Int]] = []

            func midpoint(_ a: Int, _ b: Int) -> Int {
                let key = Int64(min(a, b)) * Int64(vertexCount + triangles.count * 3) + Int64(max(a, b))
                if let cached = midpointCache[key] {
                    return cached
                }
                let mid = simd_normalize((positions[a] + positions[b]) / 2)
                let idx = positions.count
                positions.append(mid)
                midpointCache[key] = idx
                return idx
            }

            for tri in triangles {
                let a = tri[0], b = tri[1], c = tri[2]
                let ab = midpoint(a, b)
                let bc = midpoint(b, c)
                let ca = midpoint(c, a)
                newTriangles.append([a, ab, ca])
                newTriangles.append([b, bc, ab])
                newTriangles.append([c, ca, bc])
                newTriangles.append([ab, bc, ca])
            }

            triangles = newTriangles
            vertexCount = positions.count
        }

        // Scale to extents
        let radii = extents / 2
        positions = positions.map { $0 * radii }

        var mesh = Mesh(positions: positions, faces: triangles)

        if attributes.contains(.textureCoordinates) {
            mesh = mesh.withSphericalUVs()
        }

        mesh.applyAttributes(attributes)
        return mesh
    }

    /// A cube sphere built by subdividing a cube's faces into grids and projecting
    /// vertices onto a sphere. Produces quad faces with relatively uniform sizing.
    ///
    /// - Parameter subdivisions: Number of subdivisions per cube face edge (minimum 1).
    static func cubeSphere(extents: SIMD3<Float> = [1, 1, 1], subdivisions: Int = 8, attributes: MeshAttributes = .default) -> Mesh {
        let segs = max(1, subdivisions)
        let radii = extents / 2

        var positions: [SIMD3<Float>] = []
        var faces: [[Int]] = []

        // For each of the 6 cube faces, generate a grid of vertices projected onto the sphere.
        let faceAxes: [(right: SIMD3<Float>, up: SIMD3<Float>, forward: SIMD3<Float>)] = [
            (SIMD3(0, 0, -1), SIMD3(0, 1, 0), SIMD3(1, 0, 0)),   // +X
            (SIMD3(0, 0, 1), SIMD3(0, 1, 0), SIMD3(-1, 0, 0)),  // -X
            (SIMD3(1, 0, 0), SIMD3(0, 0, -1), SIMD3(0, 1, 0)),  // +Y
            (SIMD3(1, 0, 0), SIMD3(0, 0, 1), SIMD3(0, -1, 0)),  // -Y
            (SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)),   // +Z
            (SIMD3(-1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, -1))   // -Z
        ]

        for (right, up, forward) in faceAxes {
            let baseIndex = positions.count

            for row in 0...segs {
                for col in 0...segs {
                    let u = Float(col) / Float(segs) * 2 - 1
                    let v = Float(row) / Float(segs) * 2 - 1
                    let cubePos = forward + right * u + up * v
                    let spherePos = simd_normalize(cubePos) * radii
                    positions.append(spherePos)
                }
            }

            let stride = segs + 1
            for row in 0..<segs {
                for col in 0..<segs {
                    let bl = baseIndex + row * stride + col
                    let br = bl + 1
                    let tl = bl + stride
                    let tr = tl + 1
                    faces.append([bl, br, tr, tl])
                }
            }
        }

        var mesh = Mesh(positions: positions, faces: faces).welded(tolerance: 1e-6)

        if attributes.contains(.textureCoordinates) {
            mesh = mesh.withSphericalUVs()
        }

        mesh.applyAttributes(attributes)
        return mesh
    }

    /// A torus with quad faces.
    static func torus(majorSegments: Int = 32, minorSegments: Int = 16, majorRadius: Float = 0.3, minorRadius: Float = 0.15, attributes: MeshAttributes = .default) -> Mesh {
        var positions: [SIMD3<Float>] = []
        var faces: [[Int]] = []

        for major in 0..<majorSegments {
            let theta = 2 * Float.pi * Float(major) / Float(majorSegments)
            let cosTheta = cos(theta)
            let sinTheta = sin(theta)
            for minor in 0..<minorSegments {
                let phi = 2 * Float.pi * Float(minor) / Float(minorSegments)
                let cosPhi = cos(phi)
                let sinPhi = sin(phi)
                let radius = majorRadius + minorRadius * cosPhi
                positions.append(SIMD3(radius * cosTheta, minorRadius * sinPhi, radius * sinTheta))
            }
        }

        for major in 0..<majorSegments {
            let nextMajor = (major + 1) % majorSegments
            for minor in 0..<minorSegments {
                let nextMinor = (minor + 1) % minorSegments
                faces.append([
                    major * minorSegments + minor,
                    nextMajor * minorSegments + minor,
                    nextMajor * minorSegments + nextMinor,
                    major * minorSegments + nextMinor
                ])
            }
        }

        var mesh = Mesh(positions: positions, faces: faces)

        if attributes.contains(.textureCoordinates) {
            var uvs = [SIMD2<Float>](repeating: .zero, count: mesh.topology.halfEdges.count)
            var faceIndex = 0
            for major in 0..<majorSegments {
                for minor in 0..<minorSegments {
                    let faceID = HalfEdgeTopology.FaceID(raw: faceIndex)
                    let heLoop = mesh.topology.halfEdgeLoop(for: faceID)
                    let u0 = Float(major) / Float(majorSegments)
                    let u1 = Float(major + 1) / Float(majorSegments)
                    let v0 = Float(minor) / Float(minorSegments)
                    let v1 = Float(minor + 1) / Float(minorSegments)
                    // Face vertices: [current, nextMajor, nextMajor+nextMinor, current+nextMinor]
                    uvs[heLoop[0].raw] = SIMD2(u0, v0)
                    uvs[heLoop[1].raw] = SIMD2(u1, v0)
                    uvs[heLoop[2].raw] = SIMD2(u1, v1)
                    uvs[heLoop[3].raw] = SIMD2(u0, v1)
                    faceIndex += 1
                }
            }
            mesh.textureCoordinates = uvs
        }

        mesh.applyAttributes(attributes)
        return mesh
    }

    /// A cylinder with quad sides and optional n-gon caps.
    static func cylinder(segments: Int = 32, height: Float = 1.0, radius: Float = 0.5, capped: Bool = true, attributes: MeshAttributes = .default) -> Mesh {
        var positions: [SIMD3<Float>] = []
        var faces: [[Int]] = []

        let halfHeight = height / 2

        // Bottom ring
        for seg in 0..<segments {
            let angle = 2 * Float.pi * Float(seg) / Float(segments)
            positions.append(SIMD3(radius * cos(angle), -halfHeight, radius * sin(angle)))
        }
        // Top ring
        for seg in 0..<segments {
            let angle = 2 * Float.pi * Float(seg) / Float(segments)
            positions.append(SIMD3(radius * cos(angle), halfHeight, radius * sin(angle)))
        }

        // Side quads
        for seg in 0..<segments {
            let nextSeg = (seg + 1) % segments
            faces.append([seg, nextSeg, segments + nextSeg, segments + seg])
        }

        // Caps
        if capped {
            // Bottom cap (winding inward)
            let bottomCap = (0..<segments).reversed().map(\.self)
            faces.append(bottomCap)
            // Top cap
            let topCap = (0..<segments).map { $0 + segments }
            faces.append(topCap)
        }

        var mesh = Mesh(positions: positions, faces: faces)

        if attributes.contains(.textureCoordinates) {
            var uvs = [SIMD2<Float>](repeating: .zero, count: mesh.topology.halfEdges.count)

            // Side quads: unwrap around circumference
            for seg in 0..<segments {
                let faceID = HalfEdgeTopology.FaceID(raw: seg)
                let heLoop = mesh.topology.halfEdgeLoop(for: faceID)
                let u0 = Float(seg) / Float(segments)
                let u1 = Float(seg + 1) / Float(segments)
                // Face vertices: [bottom, nextBottom, nextTop, top]
                uvs[heLoop[0].raw] = SIMD2(u0, 1)
                uvs[heLoop[1].raw] = SIMD2(u1, 1)
                uvs[heLoop[2].raw] = SIMD2(u1, 0)
                uvs[heLoop[3].raw] = SIMD2(u0, 0)
            }

            // Cap UVs: project onto unit circle centered at (0.5, 0.5)
            if capped {
                let bottomFaceID = HalfEdgeTopology.FaceID(raw: segments)
                let bottomLoop = mesh.topology.halfEdgeLoop(for: bottomFaceID)
                for (i, he) in bottomLoop.enumerated() {
                    // Bottom cap is reversed, so map index back to segment
                    let seg = segments - 1 - i
                    let angle = 2 * Float.pi * Float(seg) / Float(segments)
                    uvs[he.raw] = SIMD2(0.5 + 0.5 * cos(angle), 0.5 + 0.5 * sin(angle))
                }

                let topFaceID = HalfEdgeTopology.FaceID(raw: segments + 1)
                let topLoop = mesh.topology.halfEdgeLoop(for: topFaceID)
                for (i, he) in topLoop.enumerated() {
                    let angle = 2 * Float.pi * Float(i) / Float(segments)
                    uvs[he.raw] = SIMD2(0.5 + 0.5 * cos(angle), 0.5 + 0.5 * sin(angle))
                }
            }

            mesh.textureCoordinates = uvs
        }

        mesh.applyAttributes(attributes)
        return mesh
    }

    /// A hemisphere (top half of a UV sphere) with an optional base cap.
    ///
    /// The dome faces upward (+Y). Extents control the bounding box of the full
    /// hemisphere including the flat base.
    static func hemisphere(extents: SIMD3<Float> = [1, 1, 1], segments: Int = 32, latitudeSegments: Int = 8, capped: Bool = true, attributes: MeshAttributes = .default) -> Mesh {
        let radii = extents / 2
        var positions: [SIMD3<Float>] = []
        var faces: [[Int]] = []

        // Top pole
        positions.append(SIMD3(0, radii.y, 0))

        // Latitude rings (excluding pole and equator)
        for lat in 1..<latitudeSegments {
            let theta = Float.pi / 2 * Float(lat) / Float(latitudeSegments)
            let sinTheta = sin(theta)
            let cosTheta = cos(theta)
            for lon in 0..<segments {
                let phi = 2 * Float.pi * Float(lon) / Float(segments)
                positions.append(SIMD3(radii.x * sinTheta * cos(phi), radii.y * cosTheta, radii.z * sinTheta * sin(phi)))
            }
        }

        // Equator ring
        let equatorStart = positions.count
        for lon in 0..<segments {
            let phi = 2 * Float.pi * Float(lon) / Float(segments)
            positions.append(SIMD3(radii.x * cos(phi), 0, radii.z * sin(phi)))
        }

        // Top cap triangles
        for lon in 0..<segments {
            let nextLon = (lon + 1) % segments
            faces.append([0, 1 + lon, 1 + nextLon])
        }

        // Quad strips between latitude rings
        for lat in 0..<(latitudeSegments - 1) {
            let ringStart = 1 + lat * segments
            let nextRingStart = ringStart + segments
            for lon in 0..<segments {
                let nextLon = (lon + 1) % segments
                faces.append([
                    ringStart + lon,
                    nextRingStart + lon,
                    nextRingStart + nextLon,
                    ringStart + nextLon
                ])
            }
        }

        // Base cap (flat bottom)
        if capped {
            let baseCap = (0..<segments).reversed().map { equatorStart + $0 }
            faces.append(baseCap)
        }

        var mesh = Mesh(positions: positions, faces: faces)

        if attributes.contains(.textureCoordinates) {
            let N = segments
            let L = latitudeSegments

            var uvs = [SIMD2<Float>](repeating: .zero, count: mesh.topology.halfEdges.count)

            func uv(latRing: Int, lonSlot: Int, faceLon: Int) -> SIMD2<Float> {
                let v = Float(latRing) / Float(L)
                let effectiveLon: Float
                if lonSlot == 0, faceLon == N - 1 {
                    effectiveLon = Float(N)
                } else {
                    effectiveLon = Float(lonSlot)
                }
                let u = effectiveLon / Float(N)
                return SIMD2<Float>(u, v)
            }

            var faceIndex = 0

            // Top cap triangles
            for lon in 0..<N {
                let nextLon = (lon + 1) % N
                let heLoop = mesh.topology.halfEdgeLoop(for: HalfEdgeTopology.FaceID(raw: faceIndex))
                let polU = (Float(lon) + 0.5) / Float(N)
                uvs[heLoop[0].raw] = SIMD2<Float>(polU, 0)
                uvs[heLoop[1].raw] = uv(latRing: 1, lonSlot: lon, faceLon: lon)
                uvs[heLoop[2].raw] = uv(latRing: 1, lonSlot: nextLon, faceLon: lon)
                faceIndex += 1
            }

            // Quad strips
            for lat in 0..<(L - 1) {
                for lon in 0..<N {
                    let nextLon = (lon + 1) % N
                    let heLoop = mesh.topology.halfEdgeLoop(for: HalfEdgeTopology.FaceID(raw: faceIndex))
                    let latRing = lat + 1
                    uvs[heLoop[0].raw] = uv(latRing: latRing, lonSlot: lon, faceLon: lon)
                    uvs[heLoop[1].raw] = uv(latRing: latRing + 1, lonSlot: lon, faceLon: lon)
                    uvs[heLoop[2].raw] = uv(latRing: latRing + 1, lonSlot: nextLon, faceLon: lon)
                    uvs[heLoop[3].raw] = uv(latRing: latRing, lonSlot: nextLon, faceLon: lon)
                    faceIndex += 1
                }
            }

            // Base cap UVs
            if capped {
                let capFaceID = HalfEdgeTopology.FaceID(raw: faceIndex)
                let capLoop = mesh.topology.halfEdgeLoop(for: capFaceID)
                for (i, he) in capLoop.enumerated() {
                    let seg = N - 1 - i
                    let angle = 2 * Float.pi * Float(seg) / Float(N)
                    uvs[he.raw] = SIMD2(0.5 + 0.5 * cos(angle), 0.5 + 0.5 * sin(angle))
                }
            }

            mesh.textureCoordinates = uvs
        }

        mesh.applyAttributes(attributes)
        return mesh
    }

    /// A capsule (cylinder with hemispherical caps on each end).
    ///
    /// The capsule is oriented along the Y axis. `height` is the total height
    /// including the two hemispherical caps. `radius` is the radius of the
    /// cylinder and caps.
    static func capsule(segments: Int = 32, height: Float = 1.0, radius: Float = 0.25, latitudeSegments: Int = 8, attributes: MeshAttributes = .default) -> Mesh {
        let cylinderHeight = max(0, height - 2 * radius)
        let halfCylinder = cylinderHeight / 2
        var positions: [SIMD3<Float>] = []
        var faces: [[Int]] = []

        // Top pole
        positions.append(SIMD3(0, halfCylinder + radius, 0))

        // Top hemisphere rings (excluding pole, from pole toward equator)
        for lat in 1..<latitudeSegments {
            let theta = Float.pi / 2 * Float(lat) / Float(latitudeSegments)
            let sinTheta = sin(theta)
            let cosTheta = cos(theta)
            for lon in 0..<segments {
                let phi = 2 * Float.pi * Float(lon) / Float(segments)
                positions.append(SIMD3(
                    radius * sinTheta * cos(phi),
                    halfCylinder + radius * cosTheta,
                    radius * sinTheta * sin(phi)
                ))
            }
        }

        // Top equator ring (top of cylinder)
        let topEquatorStart = positions.count
        for lon in 0..<segments {
            let phi = 2 * Float.pi * Float(lon) / Float(segments)
            positions.append(SIMD3(radius * cos(phi), halfCylinder, radius * sin(phi)))
        }

        // Bottom equator ring (bottom of cylinder)
        let bottomEquatorStart = positions.count
        for lon in 0..<segments {
            let phi = 2 * Float.pi * Float(lon) / Float(segments)
            positions.append(SIMD3(radius * cos(phi), -halfCylinder, radius * sin(phi)))
        }

        // Bottom hemisphere rings (from equator toward pole)
        let bottomHemiStart = positions.count
        for lat in 1..<latitudeSegments {
            let theta = Float.pi / 2 + Float.pi / 2 * Float(lat) / Float(latitudeSegments)
            let sinTheta = sin(theta)
            let cosTheta = cos(theta)
            for lon in 0..<segments {
                let phi = 2 * Float.pi * Float(lon) / Float(segments)
                positions.append(SIMD3(
                    radius * sinTheta * cos(phi),
                    -halfCylinder + radius * cosTheta,
                    radius * sinTheta * sin(phi)
                ))
            }
        }

        // Bottom pole
        let bottomPole = positions.count
        positions.append(SIMD3(0, -halfCylinder - radius, 0))

        // === Faces ===

        // Top hemisphere: pole cap triangles
        for lon in 0..<segments {
            let nextLon = (lon + 1) % segments
            faces.append([0, 1 + lon, 1 + nextLon])
        }

        // Top hemisphere: quad strips between rings
        for lat in 0..<(latitudeSegments - 1) {
            let ringStart = 1 + lat * segments
            let nextRingStart = ringStart + segments
            for lon in 0..<segments {
                let nextLon = (lon + 1) % segments
                faces.append([
                    ringStart + lon,
                    nextRingStart + lon,
                    nextRingStart + nextLon,
                    ringStart + nextLon
                ])
            }
        }

        // Cylinder: quads between top equator and bottom equator
        for lon in 0..<segments {
            let nextLon = (lon + 1) % segments
            faces.append([
                topEquatorStart + lon,
                bottomEquatorStart + lon,
                bottomEquatorStart + nextLon,
                topEquatorStart + nextLon
            ])
        }

        // Bottom hemisphere: quad strips between rings
        // First strip: bottom equator to first bottom hemi ring
        for lon in 0..<segments {
            let nextLon = (lon + 1) % segments
            faces.append([
                bottomEquatorStart + lon,
                bottomHemiStart + lon,
                bottomHemiStart + nextLon,
                bottomEquatorStart + nextLon
            ])
        }
        // Remaining bottom hemi quad strips
        for lat in 0..<(latitudeSegments - 2) {
            let ringStart = bottomHemiStart + lat * segments
            let nextRingStart = ringStart + segments
            for lon in 0..<segments {
                let nextLon = (lon + 1) % segments
                faces.append([
                    ringStart + lon,
                    nextRingStart + lon,
                    nextRingStart + nextLon,
                    ringStart + nextLon
                ])
            }
        }

        // Bottom pole cap triangles
        let lastRingStart = bottomHemiStart + (latitudeSegments - 2) * segments
        for lon in 0..<segments {
            let nextLon = (lon + 1) % segments
            faces.append([lastRingStart + lon, bottomPole, lastRingStart + nextLon])
        }

        var mesh = Mesh(positions: positions, faces: faces)

        if attributes.contains(.textureCoordinates) {
            let N = segments
            // Total latitude bands: top hemi (latSegs) + cylinder (1) + bottom hemi (latSegs)
            let totalBands = latitudeSegments * 2 + 1

            var uvs = [SIMD2<Float>](repeating: .zero, count: mesh.topology.halfEdges.count)

            func uv(band: Int, lonSlot: Int, faceLon: Int) -> SIMD2<Float> {
                let v = Float(band) / Float(totalBands)
                let effectiveLon: Float
                if lonSlot == 0, faceLon == N - 1 {
                    effectiveLon = Float(N)
                } else {
                    effectiveLon = Float(lonSlot)
                }
                let u = effectiveLon / Float(N)
                return SIMD2<Float>(u, v)
            }

            var faceIndex = 0

            // Top pole triangles (band 0 → 1)
            for lon in 0..<N {
                let nextLon = (lon + 1) % N
                let heLoop = mesh.topology.halfEdgeLoop(for: HalfEdgeTopology.FaceID(raw: faceIndex))
                let polU = (Float(lon) + 0.5) / Float(N)
                uvs[heLoop[0].raw] = SIMD2<Float>(polU, 0)
                uvs[heLoop[1].raw] = uv(band: 1, lonSlot: lon, faceLon: lon)
                uvs[heLoop[2].raw] = uv(band: 1, lonSlot: nextLon, faceLon: lon)
                faceIndex += 1
            }

            // Top hemisphere quad strips (bands 1..latSegs)
            for lat in 0..<(latitudeSegments - 1) {
                for lon in 0..<N {
                    let nextLon = (lon + 1) % N
                    let heLoop = mesh.topology.halfEdgeLoop(for: HalfEdgeTopology.FaceID(raw: faceIndex))
                    let band = lat + 1
                    uvs[heLoop[0].raw] = uv(band: band, lonSlot: lon, faceLon: lon)
                    uvs[heLoop[1].raw] = uv(band: band + 1, lonSlot: lon, faceLon: lon)
                    uvs[heLoop[2].raw] = uv(band: band + 1, lonSlot: nextLon, faceLon: lon)
                    uvs[heLoop[3].raw] = uv(band: band, lonSlot: nextLon, faceLon: lon)
                    faceIndex += 1
                }
            }

            // Cylinder quads (band latSegs → latSegs+1)
            let cylBand = latitudeSegments
            for lon in 0..<N {
                let nextLon = (lon + 1) % N
                let heLoop = mesh.topology.halfEdgeLoop(for: HalfEdgeTopology.FaceID(raw: faceIndex))
                uvs[heLoop[0].raw] = uv(band: cylBand, lonSlot: lon, faceLon: lon)
                uvs[heLoop[1].raw] = uv(band: cylBand + 1, lonSlot: lon, faceLon: lon)
                uvs[heLoop[2].raw] = uv(band: cylBand + 1, lonSlot: nextLon, faceLon: lon)
                uvs[heLoop[3].raw] = uv(band: cylBand, lonSlot: nextLon, faceLon: lon)
                faceIndex += 1
            }

            // Bottom hemisphere quad strips (bands latSegs+1 .. totalBands-1)
            for lat in 0..<(latitudeSegments - 1) {
                for lon in 0..<N {
                    let nextLon = (lon + 1) % N
                    let heLoop = mesh.topology.halfEdgeLoop(for: HalfEdgeTopology.FaceID(raw: faceIndex))
                    let band = latitudeSegments + 1 + lat
                    uvs[heLoop[0].raw] = uv(band: band, lonSlot: lon, faceLon: lon)
                    uvs[heLoop[1].raw] = uv(band: band + 1, lonSlot: lon, faceLon: lon)
                    uvs[heLoop[2].raw] = uv(band: band + 1, lonSlot: nextLon, faceLon: lon)
                    uvs[heLoop[3].raw] = uv(band: band, lonSlot: nextLon, faceLon: lon)
                    faceIndex += 1
                }
            }

            // Bottom pole triangles
            for lon in 0..<N {
                let nextLon = (lon + 1) % N
                let heLoop = mesh.topology.halfEdgeLoop(for: HalfEdgeTopology.FaceID(raw: faceIndex))
                let polU = (Float(lon) + 0.5) / Float(N)
                uvs[heLoop[0].raw] = uv(band: totalBands - 1, lonSlot: lon, faceLon: lon)
                uvs[heLoop[1].raw] = SIMD2<Float>(polU, 1)
                uvs[heLoop[2].raw] = uv(band: totalBands - 1, lonSlot: nextLon, faceLon: lon)
                faceIndex += 1
            }

            mesh.textureCoordinates = uvs
        }

        mesh.applyAttributes(attributes)
        return mesh
    }

    /// A cone with triangle sides and an optional n-gon base cap.
    static func cone(segments: Int = 32, height: Float = 1.0, radius: Float = 0.5, capped: Bool = true, attributes: MeshAttributes = .default) -> Mesh {
        var positions: [SIMD3<Float>] = []
        var faces: [[Int]] = []

        let halfHeight = height / 2

        // Apex
        positions.append(SIMD3(0, halfHeight, 0))

        // Base ring
        for seg in 0..<segments {
            let angle = 2 * Float.pi * Float(seg) / Float(segments)
            positions.append(SIMD3(radius * cos(angle), -halfHeight, radius * sin(angle)))
        }

        // Side triangles
        for seg in 0..<segments {
            let nextSeg = (seg + 1) % segments
            faces.append([0, 1 + nextSeg, 1 + seg])
        }

        // Base cap
        if capped {
            let baseCap = (0..<segments).map { $0 + 1 }
            faces.append(baseCap)
        }

        var mesh = Mesh(positions: positions, faces: faces)

        if attributes.contains(.textureCoordinates) {
            var uvs = [SIMD2<Float>](repeating: .zero, count: mesh.topology.halfEdges.count)

            // Side triangles: unwrap around circumference
            for seg in 0..<segments {
                let faceID = HalfEdgeTopology.FaceID(raw: seg)
                let heLoop = mesh.topology.halfEdgeLoop(for: faceID)
                let u0 = Float(seg) / Float(segments)
                let u1 = Float(seg + 1) / Float(segments)
                let uMid = (u0 + u1) / 2
                // Face vertices: [apex, nextBase, base]
                uvs[heLoop[0].raw] = SIMD2(uMid, 0) // apex
                uvs[heLoop[1].raw] = SIMD2(u1, 1)   // nextBase
                uvs[heLoop[2].raw] = SIMD2(u0, 1)   // base
            }

            // Base cap: project onto unit circle centered at (0.5, 0.5)
            if capped {
                let capFaceID = HalfEdgeTopology.FaceID(raw: segments)
                let capLoop = mesh.topology.halfEdgeLoop(for: capFaceID)
                for (i, he) in capLoop.enumerated() {
                    let angle = 2 * Float.pi * Float(i) / Float(segments)
                    uvs[he.raw] = SIMD2(0.5 + 0.5 * cos(angle), 0.5 + 0.5 * sin(angle))
                }
            }

            mesh.textureCoordinates = uvs
        }

        mesh.applyAttributes(attributes)
        return mesh
    }

    /// A conical frustum (truncated cone) with quad sides and optional n-gon caps.
    ///
    /// When `topRadius` is 0 this degenerates to a regular cone.
    static func conicalFrustum(segments: Int = 32, height: Float = 1.0, topRadius: Float = 0.25, bottomRadius: Float = 0.5, capped: Bool = true, attributes: MeshAttributes = .default) -> Mesh {
        var positions: [SIMD3<Float>] = []
        var faces: [[Int]] = []

        let halfHeight = height / 2

        // Bottom ring
        for seg in 0..<segments {
            let angle = 2 * Float.pi * Float(seg) / Float(segments)
            positions.append(SIMD3(bottomRadius * cos(angle), -halfHeight, bottomRadius * sin(angle)))
        }

        // Top ring
        let topRingStart = positions.count
        for seg in 0..<segments {
            let angle = 2 * Float.pi * Float(seg) / Float(segments)
            positions.append(SIMD3(topRadius * cos(angle), halfHeight, topRadius * sin(angle)))
        }

        // Side quads
        for seg in 0..<segments {
            let nextSeg = (seg + 1) % segments
            faces.append([seg, nextSeg, topRingStart + nextSeg, topRingStart + seg])
        }

        // Caps
        if capped {
            // Bottom cap (winding inward)
            let bottomCap = (0..<segments).reversed().map(\.self)
            faces.append(bottomCap)
            // Top cap
            let topCap = (0..<segments).map { topRingStart + $0 }
            faces.append(topCap)
        }

        var mesh = Mesh(positions: positions, faces: faces)

        if attributes.contains(.textureCoordinates) {
            var uvs = [SIMD2<Float>](repeating: .zero, count: mesh.topology.halfEdges.count)

            // Side quads: unwrap around circumference
            for seg in 0..<segments {
                let faceID = HalfEdgeTopology.FaceID(raw: seg)
                let heLoop = mesh.topology.halfEdgeLoop(for: faceID)
                let u0 = Float(seg) / Float(segments)
                let u1 = Float(seg + 1) / Float(segments)
                uvs[heLoop[0].raw] = SIMD2(u0, 1)
                uvs[heLoop[1].raw] = SIMD2(u1, 1)
                uvs[heLoop[2].raw] = SIMD2(u1, 0)
                uvs[heLoop[3].raw] = SIMD2(u0, 0)
            }

            // Cap UVs
            if capped {
                let bottomFaceID = HalfEdgeTopology.FaceID(raw: segments)
                let bottomLoop = mesh.topology.halfEdgeLoop(for: bottomFaceID)
                for (i, he) in bottomLoop.enumerated() {
                    let seg = segments - 1 - i
                    let angle = 2 * Float.pi * Float(seg) / Float(segments)
                    uvs[he.raw] = SIMD2(0.5 + 0.5 * cos(angle), 0.5 + 0.5 * sin(angle))
                }

                let topFaceID = HalfEdgeTopology.FaceID(raw: segments + 1)
                let topLoop = mesh.topology.halfEdgeLoop(for: topFaceID)
                for (i, he) in topLoop.enumerated() {
                    let angle = 2 * Float.pi * Float(i) / Float(segments)
                    uvs[he.raw] = SIMD2(0.5 + 0.5 * cos(angle), 0.5 + 0.5 * sin(angle))
                }
            }

            mesh.textureCoordinates = uvs
        }

        mesh.applyAttributes(attributes)
        return mesh
    }

    /// A rectangular frustum (truncated rectangular pyramid) with quad sides and optional caps.
    ///
    /// The bottom face is centered at `y = -height/2` with size `bottomExtents`,
    /// and the top face is centered at `y = +height/2` with size `topExtents`.
    /// When `topExtents` is zero this degenerates to a pyramid.
    static func rectangularFrustum(height: Float = 1.0, topExtents: SIMD2<Float> = [0.5, 0.5], bottomExtents: SIMD2<Float> = [1, 1], capped: Bool = true, attributes: MeshAttributes = .default) -> Mesh {
        let halfHeight = height / 2
        let bt = bottomExtents / 2
        let tt = topExtents / 2

        // Bottom: 0-3, Top: 4-7
        let positions: [SIMD3<Float>] = [
            SIMD3(-bt.x, -halfHeight, -bt.y), SIMD3(bt.x, -halfHeight, -bt.y),
            SIMD3(bt.x, -halfHeight, bt.y), SIMD3(-bt.x, -halfHeight, bt.y),
            SIMD3(-tt.x, halfHeight, -tt.y), SIMD3(tt.x, halfHeight, -tt.y),
            SIMD3(tt.x, halfHeight, tt.y), SIMD3(-tt.x, halfHeight, tt.y)
        ]

        var faces: [[Int]] = [
            [0, 1, 5, 4], // front  (-Z)
            [2, 3, 7, 6], // back   (+Z)
            [3, 0, 4, 7], // left   (-X)
            [1, 2, 6, 5] // right  (+X)
        ]

        if capped {
            faces.append([3, 2, 1, 0]) // bottom
            faces.append([4, 5, 6, 7]) // top
        }

        var mesh = Mesh(positions: positions, faces: faces)

        if attributes.contains(.textureCoordinates) {
            let quadUVs: [SIMD2<Float>] = [
                SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)
            ]
            var uvs = [SIMD2<Float>](repeating: .zero, count: mesh.topology.halfEdges.count)
            for face in mesh.topology.faces {
                let heLoop = mesh.topology.halfEdgeLoop(for: face.id)
                for (i, he) in heLoop.enumerated() {
                    uvs[he.raw] = quadUVs[i]
                }
            }
            mesh.textureCoordinates = uvs
        }

        mesh.applyAttributes(attributes)
        return mesh
    }
}

// MARK: - Bundled Meshes

public extension Mesh {
    /// The Utah teapot, loaded from a bundled OBJ file.
    ///
    /// The mesh is uniformly scaled to fit within `diameter` and centered
    /// at the origin, preserving aspect ratio.
    static func teapot(diameter: Float = 1, attributes: MeshAttributes = .default) -> Mesh {
        guard let url = Bundle.module.url(forResource: "teapot", withExtension: "obj") else {
            fatalError("teapot.obj not found in bundle")
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("No Metal device available")
        }
        let allocator = MTKMeshBufferAllocator(device: device)
        let asset = MDLAsset(url: url, vertexDescriptor: nil, bufferAllocator: allocator)
        guard let mdlMesh = asset.childObjects(of: MDLMesh.self).first as? MDLMesh else {
            fatalError("No mesh found in teapot.obj")
        }
        guard var mesh = try? Mesh(mdlMesh: mdlMesh, device: device) else {
            fatalError("Failed to convert teapot MDLMesh to Mesh")
        }
        // Strip imported attributes — we'll apply the requested ones below
        mesh.normals = nil
        mesh.textureCoordinates = nil
        mesh.tangents = nil
        mesh.bitangents = nil
        mesh.colors = nil

        mesh.fitToDiameter(diameter)

        if attributes.contains(.textureCoordinates) {
            mesh = mesh.withSphericalUVs()
        }
        mesh.applyAttributes(attributes)
        return mesh
    }
}
