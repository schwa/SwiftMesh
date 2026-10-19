import Foundation
import GeometryLite3D
import simd

/// Signed distances sampled on a regular 3D grid; negative inside the mesh.
///
/// Sample (x, y, z) sits at `origin + spacing * (x, y, z)` and is stored at `values[x + resolution.x * (y + resolution.y * z)]`
/// (x fastest), the layout of a 3D texture with width `resolution.x`, height `resolution.y` and depth `resolution.z`.
/// Samples lie on cell corners, so the first and last samples on each axis lie on the grid bounds.
public struct SignedDistanceField: Sendable, Equatable {
    public var origin: SIMD3<Float>
    public var spacing: SIMD3<Float>
    public var resolution: SIMD3<Int>
    public var values: [Float]

    public init(origin: SIMD3<Float>, spacing: SIMD3<Float>, resolution: SIMD3<Int>, values: [Float]) {
        precondition(values.count == resolution.x * resolution.y * resolution.z, "values.count must match resolution")
        self.origin = origin
        self.spacing = spacing
        self.resolution = resolution
        self.values = values
    }

    public func index(x: Int, y: Int, z: Int) -> Int {
        x + resolution.x * (y + resolution.y * z)
    }

    public func position(x: Int, y: Int, z: Int) -> SIMD3<Float> {
        origin + spacing * SIMD3<Float>(Float(x), Float(y), Float(z))
    }

    public func position(ofIndex index: Int) -> SIMD3<Float> {
        position(x: index % resolution.x, y: (index / resolution.x) % resolution.y, z: index / (resolution.x * resolution.y))
    }

    public subscript(x: Int, y: Int, z: Int) -> Float {
        values[index(x: x, y: y, z: z)]
    }
}

public extension Mesh {
    /// Distance to the surface, negative inside (by winding number), or nil when the mesh has no triangles.
    func signedDistance(at point: SIMD3<Float>, bvh: TriangleBVH? = nil) -> Float? {
        guard let distance = distance(to: point, bvh: bvh) else {
            return nil
        }
        return contains(point, bvh: bvh) ? -distance : distance
    }

    /// Bakes signed distances on a grid covering the mesh bounds grown by `padding` on every side.
    ///
    /// `resolution` is the number of samples per axis (at least 2). Use padding of a few cells so the field is
    /// positive on the grid border. Returns nil when the mesh has no triangles. Runs on all cores.
    ///
    /// Only samples within one cell spacing of the surface get their own winding-number test. Along each row, a run
    /// of farther samples cannot cross the surface and takes the sign of one test.
    func signedDistanceField(resolution: SIMD3<Int>, padding: Float = 0, bvh: TriangleBVH? = nil) -> SignedDistanceField? {
        precondition(all(resolution .>= 2), "resolution must be at least 2 on every axis")
        let bvh = bvh ?? TriangleBVH(mesh: self)
        guard !bvh.triangles.isEmpty, let bounds else {
            return nil
        }
        let origin = bounds.min - padding
        let spacing = (bounds.max - bounds.min + 2 * padding) / SIMD3<Float>(resolution &- 1)
        var field = SignedDistanceField(origin: origin, spacing: spacing, resolution: resolution, values: [Float](repeating: 0, count: resolution.x * resolution.y * resolution.z))
        let grid = field

        // Unsigned distances, one z-slice per task.
        field.values.withUnsafeMutableBufferPointer { buffer in
            // Each task writes its own slice.
            nonisolated(unsafe) let values = buffer
            DispatchQueue.concurrentPerform(iterations: resolution.z) { z in
                for y in 0..<resolution.y {
                    // Four neighbouring samples share one traversal.
                    var x = 0
                    while x + 4 <= resolution.x {
                        let start = grid.position(x: x, y: y, z: z)
                        let xs = SIMD4<Float>(repeating: origin.x) + spacing.x * SIMD4<Float>(Float(x), Float(x + 1), Float(x + 2), Float(x + 3))
                        let distances = bvh.distances(toPointsX: xs, y: SIMD4(repeating: start.y), z: SIMD4(repeating: start.z))
                        let index = grid.index(x: x, y: y, z: z)
                        for lane in 0..<4 {
                            values[index + lane] = distances[lane]
                        }
                        x += 4
                    }
                    for x in x..<resolution.x {
                        values[grid.index(x: x, y: y, z: z)] = bvh.closestPoint(to: grid.position(x: x, y: y, z: z))?.distance ?? .infinity
                    }
                }
            }
        }

        // Signs, one row per task. A step along x is at most `bandWidth` long, so it cannot cross the surface when
        // it starts farther away than that. So a run of such far samples shares one sign and needs one winding test,
        // and a sample next to a far sample takes its sign. Only samples near the surface with no far neighbour
        // along x get their own test.
        let bandWidth = spacing.max()
        field.values.withUnsafeMutableBufferPointer { buffer in
            // Each task writes its own row.
            nonisolated(unsafe) let values = buffer
            DispatchQueue.concurrentPerform(iterations: resolution.y * resolution.z) { row in
                let start = row * resolution.x
                let end = start + resolution.x
                withUnsafeTemporaryAllocation(of: Bool.self, capacity: resolution.x) { inside in
                    // Far runs.
                    var runInside: Bool?
                    for index in start..<end {
                        guard values[index] > bandWidth else {
                            runInside = nil
                            continue
                        }
                        if runInside == nil {
                            runInside = contains(grid.position(ofIndex: index), bvh: bvh)
                        }
                        inside[index - start] = runInside ?? false
                    }
                    // Near samples: from a far neighbour when there is one.
                    for index in start..<end where values[index] <= bandWidth {
                        if index > start, values[index - 1] > bandWidth {
                            inside[index - start] = inside[index - 1 - start]
                        } else if index + 1 < end, values[index + 1] > bandWidth {
                            inside[index - start] = inside[index + 1 - start]
                        } else {
                            inside[index - start] = contains(grid.position(ofIndex: index), bvh: bvh)
                        }
                    }
                    for index in start..<end where inside[index - start] {
                        values[index] = -values[index]
                    }
                }
            }
        }
        return field
    }
}
