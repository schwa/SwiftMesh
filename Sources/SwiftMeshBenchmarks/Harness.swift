import Foundation

struct Benchmark {
    var name: String
    /// Builds the input once, returns the closure to time.
    var setup: () -> () -> Void
}

struct BenchmarkResult {
    var name: String
    var iterations: Int
    var min: Duration
    var median: Duration
    var max: Duration
}

struct BenchmarkRunner {
    var minimumIterations = 5
    var maximumIterations = 1_000
    var timeBudget: Duration = .seconds(1)

    func run(_ benchmark: Benchmark) -> BenchmarkResult {
        let body = benchmark.setup()
        body() // warm-up
        let clock = ContinuousClock()
        var samples: [Duration] = []
        let deadline = clock.now + timeBudget
        while samples.count < minimumIterations || (samples.count < maximumIterations && clock.now < deadline) {
            samples.append(clock.measure(body))
        }
        samples.sort()
        return BenchmarkResult(name: benchmark.name, iterations: samples.count, min: samples[0], median: samples[samples.count / 2], max: samples[samples.count - 1])
    }
}

extension Duration {
    var milliseconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1_000 + Double(attoseconds) / 1e15
    }
}

func format(_ results: [BenchmarkResult], json: Bool) -> String {
    if json {
        let objects = results.map { result -> [String: Any] in
            ["name": result.name, "iterations": result.iterations, "min_ms": result.min.milliseconds, "median_ms": result.median.milliseconds, "max_ms": result.max.milliseconds]
        }
        let data = (try? JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
    let nameWidth = max(4, results.map(\.name.count).max() ?? 0)
    var lines = ["\("name".padding(toLength: nameWidth, withPad: " ", startingAt: 0))  \("iters".leftPadded(6))  \("min ms".leftPadded(10))  \("median ms".leftPadded(10))  \("max ms".leftPadded(10))"]
    for result in results {
        lines.append("\(result.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0))  \(String(result.iterations).leftPadded(6))  \(String(format: "%.3f", result.min.milliseconds).leftPadded(10))  \(String(format: "%.3f", result.median.milliseconds).leftPadded(10))  \(String(format: "%.3f", result.max.milliseconds).leftPadded(10))")
    }
    return lines.joined(separator: "\n")
}

extension String {
    func leftPadded(_ width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
