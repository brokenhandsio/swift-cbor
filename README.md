# swift-cbor

[![CI](https://github.com/brokenhandsio/swift-cbor/actions/workflows/ci.yml/badge.svg)](https://github.com/brokenhandsio/swift-cbor/actions/workflows/ci.yml)

A modern, memory-safe [CBOR](https://www.rfc-editor.org/rfc/rfc8949.html) (Concise
Binary Object Representation, RFC 8949) library for Swift.

- **Memory-safe by construction.** Decoding reads through `Span<UInt8>` using only
  bounds-checked access — the library contains **zero** `unsafe` code and compiles
  under `.strictMemorySafety()`.
- **Complete RFC 8949 support.** Every example in RFC 8949 Appendix A round-trips,
  including tags, indefinite-length items, half/single/double floats, and the full
  ±2⁶⁴ integer range.
- **Deterministic encoding.** Shortest-form integers and canonically ordered map
  keys (RFC 8949 §4.2) by default.
- **Fast and lean.** Benchmarked against other Swift CBOR libraries, with fewer
  allocations and lower instruction counts across decode and encode.
- **Two ways to use it.** Work with the `CBOR` value model directly, or bridge any
  `Codable` type through `CBOREncoder` / `CBORDecoder`.
- **Optional Foundation.** Foundation is only used to bridge `Data`; it lives behind
  a package trait you can switch off to build with no Foundation dependency at all.
- **`Sendable` throughout**, with a `@nonexhaustive` public API designed to evolve
  without source breaks.

## Requirements

- Swift 6.3+
- macOS 26 / iOS 26 / tvOS 26 / watchOS 26 / visionOS 26 (or any Linux with a
  Swift 6.3 toolchain)

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/brokenhandsio/swift-cbor.git", from: "0.0.1"),
],
```

Then add the `CBOR` product to your target:

```swift
.target(
    name: "MyTarget",
    dependencies: [
        .product(name: "CBOR", package: "swift-cbor"),
    ]
),
```

## Usage

### Decoding

`CBOR.decode` reads a single, complete data item and requires the entire input to
be consumed:

```swift
import CBOR

let value = try CBOR.decode([0x83, 0x01, 0x02, 0x03])
// value == .array([.unsignedInt(1), .unsignedInt(2), .unsignedInt(3)])
```

You can decode from a `[UInt8]`, an `ArraySlice<UInt8>`, or a `Span<UInt8>` directly.

### Encoding

```swift
let item: CBOR = ["temperature": 21, "unit": "C"]
let bytes = item.encode()
// Map keys are emitted in RFC 8949 deterministic order.
```

### Building and reading values

`CBOR` conforms to the relevant `ExpressibleBy*Literal` protocols, so values read
naturally in source:

```swift
let message: CBOR = [
    "id": 42,
    "tags": ["a", "b"],
    "payload": .byteString([0xde, 0xad, 0xbe, 0xef]),
    "note": nil,          // .null
]
```

Read back with subscripts and typed accessors (each returns `nil` on a mismatch):

```swift
message["id"]?.int            // 42
message["tags"]?[.unsignedInt(0)]?.string   // "a"
message["payload"]?.bytes     // [0xde, 0xad, 0xbe, 0xef]
message["note"]?.isNull       // true
```

Negative integers follow the CBOR encoding, where `.negativeInt(n)` represents
`-1 - n` (so `-1` is `.negativeInt(0)`). The `int` accessor and integer literals
hide this for you:

```swift
let alg: CBOR = -7            // .negativeInt(6)
alg.int                       // -7
```

### Codable

Bridge any `Encodable` / `Decodable` type, mirroring `JSONEncoder` / `JSONDecoder`:

```swift
struct Reading: Codable {
    var sensor: String
    var value: Double
    var ok: Bool
}

let bytes = try CBOREncoder().encode(Reading(sensor: "abc", value: 1.5, ok: true))
let reading = try CBORDecoder().decode(Reading.self, from: bytes)
```

Swift structs encode to CBOR maps keyed by their property names, in deterministic
key order. With the `FoundationSupport` trait enabled (the default), `Data`
properties encode as CBOR byte strings.

### Decoding an embedded item

When a CBOR item is embedded in a larger buffer, `decodeFirst` returns the value
along with how many bytes it consumed — useful for slicing out whatever follows it:

```swift
let (value, consumed) = try CBOR.decodeFirst(buffer)
let remainder = buffer[consumed...]
```

### Options

```swift
let options = CBOROptions(
    maximumDepth: 16,            // bound nesting on adversarial input (default 512)
    rejectDuplicateMapKeys: true // throw on duplicate map keys (default false)
)
let value = try CBOR.decode(bytes, options: options)
```

`CBOROptions` also controls `deterministic` encoding, which is on by default.

### Tags

Tagged items use `CBORTag`, which comes with the common IANA tags:

```swift
let tagged: CBOR = .tagged(.uri, .textString("https://example.com"))
let custom: CBOR = .tagged(CBORTag(1668546817), .array([1, 2, 3]))
```

## Building without Foundation

Foundation is only linked to bridge `Data` in the Codable layer, and it is gated
behind the default-on `FoundationSupport` trait. To build with no Foundation
dependency, disable default traits:

```swift
.package(
    url: "https://github.com/brokenhandsio/swift-cbor.git",
    from: "0.0.1",
    traits: [] // enable no traits, omitting the default FoundationSupport
),
```

or, when building this package directly, from the command line:

```sh
swift build --disable-default-traits
swift test --disable-default-traits
```

With the trait off, the entire value model, the `Span`-based parser, value-model
encode/decode, and the Codable bridge for all non-`Data` types are available with
no Foundation linked. (`Data` properties then encode via standard `Codable` as an
array of integers rather than a byte string.)

## Documentation

API documentation is built with [DocC](https://www.swift.org/documentation/docc/).
The DocC plugin is gated behind an environment flag so consumers of the library never
resolve it:

```sh
CBOR_DOCC=1 swift package generate-documentation --target CBOR
```

## Benchmarks

Benchmarks use [ordo-one/benchmark](https://github.com/ordo-one/benchmark) and live
under `Benchmarks/`. They are likewise gated behind an environment flag so the
harness's dependency tree never reaches library consumers — a plain `import CBOR`
resolves with **zero** external dependencies:

```sh
CBOR_BENCHMARK=1 swift package benchmark
```

They cover COSE-key decode/encode, large array/map throughput, full round-trips, and
the Codable bridge. CI gates regressions on **instruction count** and **allocation
count** — deterministic metrics — alongside peak resident memory. swift-cbor has been
benchmarked against other Swift CBOR libraries and shows improvements across both
allocation count and instruction count.

## Limits

Like any Swift CBOR library built on a recursive value type, a decoded `CBOR` value is
**deallocated recursively** — freeing a value nested many thousands of levels deep can
exhaust the stack. Decoding and encoding themselves are fully iterative and never
recurse on input nesting, and `CBOROptions.maximumDepth` (default 512) bounds how deep
a decoded value can be, so values decoded from untrusted input free safely on ordinary
stacks. Lower `maximumDepth` if you decode on threads with unusually small stacks.

## License

swift-cbor is available under the MIT license. See [LICENSE](LICENSE) for details.
