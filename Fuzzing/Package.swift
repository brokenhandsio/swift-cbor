// swift-tools-version: 6.3
import PackageDescription

// Fuzzing lives in its own package so that instrumented builds — which are unfit
// for any other purpose — get their own .build directory, and so the main
// package's `swift build` and `swift test` stay clean. Nothing here is visible
// to consumers of the CBOR library.
//
// Run a target with:
//   swift package --allow-writing-to-package-directory fuzz CBORDecode --time 60
let package = Package(
    name: "Fuzzing",
    platforms: [.macOS(.v26)],
    dependencies: [
        // The `package:` label for a path dependency is the *directory* name,
        // not the name declared in its Package.swift.
        .package(path: "../"),
        .package(url: "https://github.com/brokenhandsio/swift-fuzz.git", from: "0.4.0"),
    ],
    targets: [
        // Each fuzz target is a pair: a pure-C executable holding libFuzzer's
        // entry points, and a Swift library holding the actual harness. See the
        // comment in shim.c for why the executable cannot be Swift.
        .executableTarget(
            name: "CBORDecode",
            dependencies: ["CBORDecodeTarget"],
            path: "FuzzTargets/CBORDecodeShim"
        ),
        .target(
            name: "CBORDecodeTarget",
            dependencies: [
                .product(name: "Fuzzing", package: "swift-fuzz"),
                .product(name: "CBOR", package: "swift-cbor"),
            ],
            path: "FuzzTargets/CBORDecode",
            plugins: [.plugin(name: "FuzzTargetPlugin", package: "swift-fuzz")]
        ),

        .executableTarget(
            name: "CBORRoundTrip",
            dependencies: ["CBORRoundTripTarget"],
            path: "FuzzTargets/CBORRoundTripShim"
        ),
        .target(
            name: "CBORRoundTripTarget",
            dependencies: [
                .product(name: "Fuzzing", package: "swift-fuzz"),
                .product(name: "CBOR", package: "swift-cbor"),
            ],
            path: "FuzzTargets/CBORRoundTrip",
            plugins: [.plugin(name: "FuzzTargetPlugin", package: "swift-fuzz")]
        ),

        .executableTarget(
            name: "CBORDeepNesting",
            dependencies: ["CBORDeepNestingTarget"],
            path: "FuzzTargets/CBORDeepNestingShim"
        ),
        .target(
            name: "CBORDeepNestingTarget",
            dependencies: [
                .product(name: "Fuzzing", package: "swift-fuzz"),
                .product(name: "CBOR", package: "swift-cbor"),
            ],
            path: "FuzzTargets/CBORDeepNesting",
            plugins: [.plugin(name: "FuzzTargetPlugin", package: "swift-fuzz")]
        ),

        .executableTarget(
            name: "CBOROptions",
            dependencies: ["CBOROptionsTarget"],
            path: "FuzzTargets/CBOROptionsShim"
        ),
        .target(
            name: "CBOROptionsTarget",
            dependencies: [
                .product(name: "Fuzzing", package: "swift-fuzz"),
                .product(name: "CBOR", package: "swift-cbor"),
            ],
            path: "FuzzTargets/CBOROptions",
            plugins: [.plugin(name: "FuzzTargetPlugin", package: "swift-fuzz")]
        ),

    ]
)
