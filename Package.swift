// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let extraSettings: [SwiftSetting] = [
    .strictMemorySafety(),
    .enableExperimentalFeature("SuppressedAssociatedTypesWithDefaults"),
    .enableExperimentalFeature("LifetimeDependence"),
    .enableExperimentalFeature("Lifetimes"),
    .enableUpcomingFeature("LifetimeDependence"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

let package = Package(
    name: "swift-cbor",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .macCatalyst(.v26),
        .visionOS(.v26),
        .watchOS(.v26),
    ],
    products: [
        .library(
            name: "CBOR",
            targets: ["CBOR"]
        ),
    ],
    dependencies: [
        // Benchmarking harness. >= 1.35.0 no longer requires jemalloc / system deps.
        .package(url: "https://github.com/ordo-one/benchmark", from: "1.35.0"),
    ],
    targets: [
        // The library itself. Strict memory safety and the modern language features
        // are applied here (and to its tests) only.
        .target(
            name: "CBOR",
            swiftSettings: extraSettings
        ),
        .testTarget(
            name: "CBORTests",
            dependencies: ["CBOR"],
            swiftSettings: extraSettings
        ),
        // Benchmarks live under Benchmarks/ so the package-benchmark plugin discovers
        // them. Deliberately NOT built with `extraSettings`: the benchmark harness is
        // not strict-memory-safe, and benchmarks are not shipped to library consumers.
        .executableTarget(
            name: "CBORBenchmarks",
            dependencies: [
                "CBOR",
                .product(name: "Benchmark", package: "benchmark"),
            ],
            path: "Benchmarks/CBORBenchmarks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "benchmark"),
            ]
        ),
    ]
)
