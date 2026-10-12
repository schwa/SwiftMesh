import BinPacking
import Foundation
import Metal
import simd
import SwiftMesh
import SwiftMeshIO
import SwiftUI

// Usage: swift run -c release SwiftMeshBenchmarks [--json] [name-filter...]

/// Deterministic points in the unit ball shell, so runs are comparable.
func randomPoints(_ count: Int, seed: UInt64 = 1) -> [SIMD3<Float>] {
    var state = seed
    func next() -> Float {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Float(state >> 40) / Float(1 << 24) * 2 - 1
    }
    return (0..<count).map { _ in simd_normalize(SIMD3(next(), next(), next())) * (0.9 + 0.1 * abs(next())) }
}

/// CSG operands by size: icosphere subdivisions 1 / 2 / 3 against an offset box.
let csgSizes: [(name: String, subdivisions: Int)] = [("small", 1), ("medium", 2), ("large", 3)]
let csgOperations: [(name: String, run: (Mesh, Mesh) -> Mesh)] = [
    ("union", { $0.union($1) }), ("intersection", { $0.intersection($1) }), ("difference", { $0.difference($1) })
]

var benchmarks: [Benchmark] = []

// Primitives
for (name, make) in [("icoSphere5", { Mesh.icoSphere(subdivisions: 5) }), ("sphere64x128", { Mesh.sphere(latitudeSegments: 64, longitudeSegments: 128) }), ("torus", { Mesh.torus() }), ("teapot", { Mesh.teapot() })] as [(String, () -> Mesh)] {
    benchmarks.append(Benchmark(name: "primitive.\(name)") { { _ = make() } })
}

// Topology
benchmarks.append(Benchmark(name: "topology.build.icoSphere5") {
    let mesh = Mesh.icoSphere(subdivisions: 5, attributes: [])
    let faces = mesh.topology.faces.map { HalfEdgeTopology.FaceDefinition(outer: mesh.topology.vertexLoop(for: $0.id).map(\.raw)) }
    let vertexCount = mesh.vertexCount
    return { _ = HalfEdgeTopology(vertexCount: vertexCount, faces: faces) }
})

// CSG
for size in csgSizes {
    for operation in csgOperations {
        benchmarks.append(Benchmark(name: "csg.\(operation.name).\(size.name)") {
            let sphere = Mesh.icoSphere(extents: [0.8, 0.8, 0.8], subdivisions: size.subdivisions, attributes: [])
            let cube = Mesh.box(extents: [0.5, 0.5, 0.5], attributes: []).translated(by: [0.2, 0.2, 0.2])
            return { _ = operation.run(sphere, cube) }
        })
    }
}

// Decimation
for ratio in [0.5, 0.25, 0.1] as [Float] {
    benchmarks.append(Benchmark(name: "decimate.icoSphere5.\(Int(ratio * 100))%") {
        let mesh = Mesh.icoSphere(subdivisions: 5, attributes: [])
        return { _ = mesh.decimated(ratio: ratio) }
    })
}

// Subdivision
for iterations in 1...3 {
    benchmarks.append(Benchmark(name: "subdivide.loop.icoSphere2.x\(iterations)") {
        let mesh = Mesh.icoSphere(subdivisions: 2, attributes: [])
        return { _ = mesh.loopSubdivided(iterations: iterations) }
    })
    benchmarks.append(Benchmark(name: "subdivide.catmullClark.box.x\(iterations)") {
        let mesh = Mesh.box(attributes: []).catmullClarkSubdivided(iterations: 2)
        return { _ = mesh.catmullClarkSubdivided(iterations: iterations) }
    })
}

// Convex hull
for count in [100, 10_000, 100_000] {
    benchmarks.append(Benchmark(name: "convexHull.\(count)") {
        let points = randomPoints(count)
        return { _ = Mesh.convexHull(of: points, attributes: []) }
    })
}

// Marching cubes
for resolution in [32, 64] {
    benchmarks.append(Benchmark(name: "marchingCubes.sphere.\(resolution)") {
        { _ = Mesh.marchingCubes(resolution: SIMD3(repeating: resolution)) { simd_length($0) - 0.4 } }
    })
}

// MetalMesh
if let device = MTLCreateSystemDefaultDevice() {
    for (layoutName, layout) in [("interleaved", MetalMesh.BufferLayout.interleaved), ("separate", .separateBuffers)] {
        benchmarks.append(Benchmark(name: "metalMesh.\(layoutName).icoSphere5") {
            let mesh = Mesh.icoSphere(subdivisions: 5, attributes: [.smoothNormals, .textureCoordinates])
            return { _ = MetalMesh(mesh: mesh, device: device, bufferLayout: layout) }
        })
    }
}

// Bin packing: RoomPlan-like charts in pixels at ~256 texels/m. 145 large surfaces
// (walls, floors) plus 100 boxes with 6 small faces each = 745 charts.
func roomPlanChartSizes() -> [SIMD2<Int>] {
    var state: UInt64 = 7
    func next(_ range: ClosedRange<Int>) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return range.lowerBound + Int(state >> 33) % (range.upperBound - range.lowerBound + 1)
    }
    var sizes = (0..<145).map { _ in SIMD2(next(60...420), next(60...300)) }
    for _ in 0..<100 {
        let box = SIMD3(next(10...120), next(10...120), next(10...120))
        sizes += [[box.x, box.y], [box.x, box.y], [box.y, box.z], [box.y, box.z], [box.x, box.z], [box.x, box.z]]
    }
    return sizes
}
benchmarks.append(Benchmark(name: "binPacking.maxRects.roomPlan745") {
    let sizes = roomPlanChartSizes()
    return {
        var packer = MaxRectsPacker<Int>(binSize: [4_096, 4_096], padding: 2)
        _ = packer.pack(sizes)
    }
})

// Robust Boolean broad phase: edges of a rotated icoSphere4 against a face BVH of icoSphere5.
benchmarks.append(Benchmark(name: "collider.build.icoSphere5") {
    let mesh = try! BooleanMesh(mesh: .icoSphere(subdivisions: 5, attributes: []))
    return { _ = mesh.makeFaceCollider() }
})
benchmarks.append(Benchmark(name: "collider.edgeQueries.icoSphere4vs5") {
    let rotation = simd_float4x4(simd_quatf(angle: 0.4, axis: simd_normalize([1, 2, 3])))
    let p = try! BooleanMesh(mesh: Mesh.icoSphere(subdivisions: 4, attributes: []).transformed(by: rotation))
    let collider = try! BooleanMesh(mesh: .icoSphere(subdivisions: 5, attributes: [])).makeFaceCollider()
    return {
        var hits = 0
        for edge in p.halfedges where edge.startVert < edge.endVert {
            collider.forEachOverlap(BooleanBox(p.vertPos[edge.startVert], p.vertPos[edge.endVert])) { _ in hits += 1 }
        }
        precondition(hits > 0)
    }
})

// IO
benchmarks.append(Benchmark(name: "ply.roundTrip.icoSphere4") {
    let mesh = Mesh.icoSphere(subdivisions: 4, attributes: [.smoothNormals])
    return { _ = try? PLY.read(from: PLY.write(mesh)) }
})
benchmarks.append(Benchmark(name: "ply.roundTrip.binary.icoSphere4") {
    let mesh = Mesh.icoSphere(subdivisions: 4, attributes: [.smoothNormals])
    return { _ = try? PLY.read(from: PLY.write(mesh, format: .binaryLittleEndian)) }
})

var arguments = Array(CommandLine.arguments.dropFirst())
let json = arguments.contains("--json")
arguments.removeAll { $0 == "--json" }

// Thin-wall extrusion: a rectangle takes the miter path; the star and text need the CSG path.
let starPath: Path = {
    var path = Path()
    path.addLines((0..<10).map { index in
        let angle = Double(index) / 10 * 2 * .pi
        let radius = index.isMultiple(of: 2) ? 2.0 : 0.5
        return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
    })
    path.closeSubpath()
    return path
}()
benchmarks.append(Benchmark(name: "extrude.thinWalls.rectangle") {
    { _ = Mesh.extruded(Path(CGRect(x: 0, y: 0, width: 4, height: 2)), depth: 1, mode: .thinWalls(thickness: 0.2), attributes: []) }
})
benchmarks.append(Benchmark(name: "extrude.thinWalls.star") {
    { _ = Mesh.extruded(starPath, depth: 1, mode: .thinWalls(thickness: 0.25), attributes: []) }
})
for text in ["A", "Hello"] {
    benchmarks.append(Benchmark(name: "extrude.thinWalls.text.\(text)") {
        { _ = Mesh.extrudedText(text, depth: 0.2, mode: .thinWalls(thickness: 0.03), attributes: []) }
    })
    benchmarks.append(Benchmark(name: "extrude.solid.text.\(text)") {
        { _ = Mesh.extrudedText(text, depth: 0.2, attributes: []) }
    })
}

let selected = arguments.isEmpty ? benchmarks : benchmarks.filter { benchmark in arguments.contains { benchmark.name.contains($0) } }
let runner = BenchmarkRunner()
var results: [BenchmarkResult] = []
for benchmark in selected {
    if !json {
        FileHandle.standardError.write(Data("running \(benchmark.name)…\n".utf8))
    }
    results.append(runner.run(benchmark))
}
print(format(results, json: json))
