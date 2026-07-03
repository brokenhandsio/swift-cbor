import Benchmark

// Placeholder benchmark suite so the target compiles and `swift package benchmark`
// runs in CI. The real encode/decode benchmarks are added in a later step.
let benchmarks: @Sendable () -> Void = {
    Benchmark("placeholder") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole((0..<256).reduce(0, &+))
        }
    }
}
