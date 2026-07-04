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
    traits: [
        .trait(
            name: "FoundationSupport",
            description: """
                Enables Foundation-backed conveniences in the Codable bridge — most \
                notably encoding/decoding `Data` as a CBOR byte string. Enabled by \
                default; disable it to build the library without linking Foundation.
                """
        ),
        .default(enabledTraits: ["FoundationSupport"]),
    ],
    dependencies: [],
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
    ]
)

// MARK: - Development-only dependencies
//
// These pull in dependency trees that library consumers should never have to
// resolve, so they are wired up only when their environment flag is set. A normal
// `import CBOR` therefore resolves with zero external dependencies.

// Benchmarks (ordo-one/benchmark + its transitive tree). CI sets CBOR_BENCHMARK=1.
if Context.environment["CBOR_BENCHMARK"] != nil {
    package.dependencies.append(
        .package(url: "https://github.com/ordo-one/benchmark", from: "1.35.0")
    )
    package.targets.append(
        // Benchmarks live under Benchmarks/ so the benchmark plugin discovers them.
        // Deliberately NOT built with `extraSettings`: the harness is not
        // strict-memory-safe, and benchmarks are never shipped to consumers.
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
        )
    )
}

// DocC documentation plugin. CI sets CBOR_DOCC=1 when building the docs archive.
if Context.environment["CBOR_DOCC"] != nil {
    package.dependencies.append(
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0")
    )
}
