import simd

// MARK: - Platonic Solids

public extension Mesh {
    static let tetrahedron: Mesh = {
        let positions: [SIMD3<Float>] = [
            SIMD3(1, 1, 1), SIMD3(-1, -1, 1), SIMD3(-1, 1, -1), SIMD3(1, -1, -1)
        ].map { simd_normalize($0) }
        return Mesh(positions: positions, faces: [
            [0, 1, 2], [0, 3, 1], [0, 2, 3], [1, 3, 2]
        ])
    }()

    static let cube: Mesh = {
        let positions: [SIMD3<Float>] = [
            SIMD3(-1, -1, -1), SIMD3(1, -1, -1), SIMD3(1, 1, -1), SIMD3(-1, 1, -1),
            SIMD3(-1, -1, 1), SIMD3(1, -1, 1), SIMD3(1, 1, 1), SIMD3(-1, 1, 1)
        ].map { simd_normalize($0) }
        return Mesh(positions: positions, faces: [
            [0, 3, 2, 1], [4, 5, 6, 7],
            [0, 1, 5, 4], [3, 7, 6, 2],
            [1, 2, 6, 5], [0, 4, 7, 3]
        ])
    }()

    static let octahedron: Mesh = {
        let positions: [SIMD3<Float>] = [
            SIMD3(1, 0, 0), SIMD3(-1, 0, 0), SIMD3(0, 1, 0),
            SIMD3(0, -1, 0), SIMD3(0, 0, 1), SIMD3(0, 0, -1)
        ]
        return Mesh(positions: positions, faces: [
            [0, 2, 4], [0, 4, 3], [0, 3, 5], [0, 5, 2],
            [1, 2, 5], [1, 5, 3], [1, 3, 4], [1, 4, 2]
        ])
    }()

    static let icosahedron: Mesh = {
        let phi: Float = (1.0 + sqrt(5.0)) / 2.0
        let positions: [SIMD3<Float>] = [
            SIMD3(-1, phi, 0), SIMD3(1, phi, 0), SIMD3(-1, -phi, 0), SIMD3(1, -phi, 0),
            SIMD3(0, -1, phi), SIMD3(0, 1, phi), SIMD3(0, -1, -phi), SIMD3(0, 1, -phi),
            SIMD3(phi, 0, -1), SIMD3(phi, 0, 1), SIMD3(-phi, 0, -1), SIMD3(-phi, 0, 1)
        ].map { simd_normalize($0) }
        return Mesh(positions: positions, faces: [
            [0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
            [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
            [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
            [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]
        ])
    }()

    static let dodecahedron: Mesh = {
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
        return Mesh(positions: positions, faces: [
            [0, 8, 10, 2, 16], [0, 16, 17, 1, 12], [0, 12, 14, 4, 8],
            [1, 17, 3, 11, 9], [1, 9, 5, 14, 12], [2, 10, 6, 15, 13],
            [2, 13, 3, 17, 16], [3, 13, 15, 7, 11], [4, 14, 5, 19, 18],
            [4, 18, 6, 10, 8], [5, 9, 11, 7, 19], [6, 18, 19, 7, 15]
        ])
    }()
}

// MARK: - Simple Primitives

public extension Mesh {
    /// A single triangle in the XY plane.
    static func triangle() -> Mesh {
        Mesh(positions: [
            SIMD3(0, 0.5, 0), SIMD3(-0.5, -0.5, 0), SIMD3(0.5, -0.5, 0)
        ], faces: [[0, 1, 2]])
    }

    /// A unit quad in the XY plane (−0.5 to 0.5).
    static func quad() -> Mesh {
        Mesh(positions: [
            SIMD3(-0.5, -0.5, 0), SIMD3(0.5, -0.5, 0),
            SIMD3(0.5, 0.5, 0), SIMD3(-0.5, 0.5, 0)
        ], faces: [[0, 1, 2, 3]])
    }

    /// A unit box (−0.5 to 0.5) with quad faces.
    static func box() -> Mesh {
        let positions: [SIMD3<Float>] = [
            SIMD3(-0.5, -0.5, 0.5), SIMD3(0.5, -0.5, 0.5),
            SIMD3(0.5, 0.5, 0.5), SIMD3(-0.5, 0.5, 0.5),
            SIMD3(-0.5, -0.5, -0.5), SIMD3(0.5, -0.5, -0.5),
            SIMD3(0.5, 0.5, -0.5), SIMD3(-0.5, 0.5, -0.5)
        ]
        return Mesh(positions: positions, faces: [
            [0, 1, 2, 3],     // front
            [5, 4, 7, 6],     // back
            [4, 0, 3, 7],     // left
            [1, 5, 6, 2],     // right
            [3, 2, 6, 7],     // top
            [4, 5, 1, 0]      // bottom
        ])
    }
}

// MARK: - Parametric Surfaces

public extension Mesh {
    /// A UV sphere with quad faces (and triangle caps at the poles).
    static func sphere(latitudeSegments: Int = 16, longitudeSegments: Int = 32) -> Mesh {
        var positions: [SIMD3<Float>] = []
        var faces: [[Int]] = []

        // Top pole
        positions.append(SIMD3(0, 1, 0))

        // Latitude rings (excluding poles)
        for lat in 1..<latitudeSegments {
            let theta = Float.pi * Float(lat) / Float(latitudeSegments)
            let sinTheta = sin(theta)
            let cosTheta = cos(theta)
            for lon in 0..<longitudeSegments {
                let phi = 2 * Float.pi * Float(lon) / Float(longitudeSegments)
                positions.append(SIMD3(sinTheta * cos(phi), cosTheta, sinTheta * sin(phi)))
            }
        }

        // Bottom pole
        let bottomPole = positions.count
        positions.append(SIMD3(0, -1, 0))

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

        return Mesh(positions: positions, faces: faces)
    }

    /// A torus with quad faces.
    static func torus(majorSegments: Int = 32, minorSegments: Int = 16, majorRadius: Float = 0.3, minorRadius: Float = 0.15) -> Mesh {
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

        return Mesh(positions: positions, faces: faces)
    }

    /// A cylinder with quad sides and optional n-gon caps.
    static func cylinder(segments: Int = 32, height: Float = 1.0, radius: Float = 0.5, capped: Bool = true) -> Mesh {
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
            let bottomCap = (0..<segments).reversed().map { $0 }
            faces.append(bottomCap)
            // Top cap
            let topCap = (0..<segments).map { $0 + segments }
            faces.append(topCap)
        }

        return Mesh(positions: positions, faces: faces)
    }

    /// A cone with triangle sides and an optional n-gon base cap.
    static func cone(segments: Int = 32, height: Float = 1.0, radius: Float = 0.5, capped: Bool = true) -> Mesh {
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

        return Mesh(positions: positions, faces: faces)
    }
}
