import Benchmark
import CBOR

// MARK: - Fixtures
//
// Decode inputs are constructed as raw byte arrays (valid canonical CBOR) so they
// never depend on this library's own encoder.

/// A COSE EC2 P-256 public key (RFC 9052 §7), in CTAP2 canonical order:
/// {1: 2, 3: -7, -1: 1, -2: h'a1…'(32), -3: h'b2…'(32)}.
let coseKeyBytes: [UInt8] = {
    var bytes: [UInt8] = [
        0xa5,             // map(5)
        0x01, 0x02,       // 1: 2
        0x03, 0x26,       // 3: -7
        0x20, 0x01,       // -1: 1
        0x21, 0x58, 0x20, // -2: bytes(32)
    ]
    bytes += Array(repeating: 0xa1, count: 32)
    bytes += [0x22, 0x58, 0x20] // -3: bytes(32)
    bytes += Array(repeating: 0xb2, count: 32)
    return bytes
}()

/// The same COSE key as an in-memory value, for the encode benchmarks.
let coseKeyValue: CBOR = [
    .unsignedInt(1): .unsignedInt(2),
    .unsignedInt(3): .negativeInt(6),
    .negativeInt(0): .unsignedInt(1),
    .negativeInt(1): .byteString(Array(repeating: 0xa1, count: 32)),
    .negativeInt(2): .byteString(Array(repeating: 0xb2, count: 32)),
]

/// A 1000-element array of small unsigned integers (each a single CBOR byte).
let intArrayBytes: [UInt8] = [0x99, 0x03, 0xe8] + (0..<1000).map { UInt8($0 % 24) }
let intArrayValue: CBOR = .array((0..<1000).map { .unsignedInt(UInt64($0 % 24)) })

/// A 128-entry integer-keyed map, for the encode benchmark.
let mapValue: CBOR = {
    var map: [CBOR: CBOR] = .init(minimumCapacity: 128)
    for index in 0..<128 {
        map[.unsignedInt(UInt64(index))] = .unsignedInt(UInt64(index &* 3))
    }
    return .map(map)
}()

struct Person: Codable {
    var name: String
    var age: Int
    var scores: [Double]
    var active: Bool
}

let person = Person(name: "Ada Lovelace", age: 36, scores: [1.5, 2.25, -3.0, 99.0], active: true)

/// Encoding of `Point(x: 1, y: 2)`: a2 6178 01 6179 02.
let pointBytes: [UInt8] = [0xa2, 0x61, 0x78, 0x01, 0x61, 0x79, 0x02]
struct Point: Codable { var x: Int; var y: Int }

// MARK: - Benchmarks

let benchmarks: @Sendable () -> Void = {
    // Instruction count and allocation count are deterministic across runs, so they
    // make reliable regression gates — unlike wall-clock time, which is noisy.
    // Peak resident memory tracks the high-water mark of the working set.
    Benchmark.defaultConfiguration.metrics = [
        .instructions, .mallocCountTotal, .peakMemoryResident,
    ]
    Benchmark.defaultConfiguration.maxIterations = 100_000

    Benchmark("Decode/COSE key") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try CBOR.decode(coseKeyBytes))
        }
    }

    Benchmark("Decode/1000-int array") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try CBOR.decode(intArrayBytes))
        }
    }

    Benchmark("Encode/COSE key") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(coseKeyValue.encode())
        }
    }

    Benchmark("Encode/1000-int array") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(intArrayValue.encode())
        }
    }

    Benchmark("Encode/128-entry map") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(mapValue.encode())
        }
    }

    Benchmark("RoundTrip/COSE key decode+encode") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try CBOR.decode(coseKeyBytes).encode())
        }
    }

    Benchmark("Codable/encode Person") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try CBOREncoder().encode(person))
        }
    }

    Benchmark("Codable/decode Point") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try CBORDecoder().decode(Point.self, from: pointBytes))
        }
    }
}
