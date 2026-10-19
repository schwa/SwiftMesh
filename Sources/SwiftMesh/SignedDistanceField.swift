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
    /// Only samples within one cell spacing of the surface get their own winding-number test. The other samples
    /// form regions that the surface cannot cross, and each region takes the sign of one test.
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
        let sliceCount = resolution.x * resolution.y
        field.values.withUnsafeMutableBufferPointer { buffer in
            // Each task writes its own slice.
            nonisolated(unsafe) let values = buffer
            DispatchQueue.concurrentPerform(iterations: resolution.z) { z in
                for y in 0..<resolution.y {
                    for x in 0..<resolution.x {
                        values[grid.index(x: x, y: y, z: z)] = bvh.closestPoint(to: grid.position(x: x, y: y, z: z))?.distance ?? .infinity
                    }
                }
            }
        }

        // A 6-neighbour step is at most `bandWidth` long, so it cannot cross the surface when its start is farther away.
        let bandWidth = spacing.max()
        let band = field.values.indices.filter { field.values[$0] <= bandWidth }

        var inside = [Bool](repeating: false, count: field.values.count)
        inside.withUnsafeMutableBufferPointer { buffer in
            // Band indices are unique, so tasks never write the same element.
            nonisolated(unsafe) let inside = buffer
            DispatchQueue.concurrentPerform(iterations: band.count) { bandIndex in
                inside[band[bandIndex]] = contains(grid.position(ofIndex: band[bandIndex]), bvh: bvh)
            }
        }

        // Flood each region of far samples from one seed and give it the seed's sign.
        var visited = [Bool](repeating: false, count: field.values.count)
        for index in band {
            visited[index] = true
        }
        var stack: [Int] = []
        for seed in field.values.indices where !visited[seed] {
            let seedInside = contains(grid.position(ofIndex: seed), bvh: bvh)
            visited[seed] = true
            stack.append(seed)
            while let index = stack.popLast() {
                inside[index] = seedInside
                let x = index % resolution.x
                let y = (index / resolution.x) % resolution.y
                let z = index / sliceCount
                for (neighbour, valid) in [
                    (index - 1, x > 0), (index + 1, x < resolution.x - 1),
                    (index - resolution.x, y > 0), (index + resolution.x, y < resolution.y - 1),
                    (index - sliceCount, z > 0), (index + sliceCount, z < resolution.z - 1)
                ] where valid && !visited[neighbour] {
                    visited[neighbour] = true
                    stack.append(neighbour)
                }
            }
        }

        for index in field.values.indices where inside[index] {
            field.values[index] = -field.values[index]
        }
        return field
    }
}
