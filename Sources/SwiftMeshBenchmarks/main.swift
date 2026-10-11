import Foundation
import simd
import SwiftMesh

// Usage: swift run -c release SwiftMeshBenchmarks [--json] [name-filter...]

let benchmarks: [Benchmark] = [
    Benchmark(name: "topology.build.icoSphere5") {
        let mesh = Mesh.icoSphere(subdivisions: 5, attributes: [])
        let faces = mesh.topology.faces.map { HalfEdgeTopology.FaceDefinition(outer: mesh.topology.vertexLoop(for: $0.id).map(\.raw)) }
        let vertexCount = mesh.vertexCount
        return { _ = HalfEdgeTopology(vertexCount: vertexCount, faces: faces) }
    },
    Benchmark(name: "decimate.icoSphere5.25%") {
        let mesh = Mesh.icoSphere(subdivisions: 5, attributes: [])
        return { _ = mesh.decimated(ratio: 0.25) }
    },
    Benchmark(name: "convexHull.sphere20k") {
        var generator = SystemRandomNumberGenerator()
        let points = (0..<20_000).map { _ in
            simd_normalize(SIMD3<Float>(Float.random(in: -1...1, using: &generator), Float.random(in: -1...1, using: &generator), Float.random(in: -1...1, using: &generator))) * Float.random(in: 0.9...1, using: &generator)
        }
        return { _ = Mesh.convexHull(of: points, attributes: []) }
    },
    Benchmark(name: "csg.difference.sphere-cube") {
        let sphere = Mesh.icoSphere(extents: [0.8, 0.8, 0.8], subdivisions: 3, attributes: [])
        let cube = Mesh.box(extents: [0.5, 0.5, 0.5], attributes: []).translated(by: [0.2, 0.2, 0.2])
        return { _ = sphere.difference(cube) }
    }
]

var arguments = Array(CommandLine.arguments.dropFirst())
let json = arguments.contains("--json")
arguments.removeAll { $0 == "--json" }

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
