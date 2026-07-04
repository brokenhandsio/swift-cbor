import Testing
import CBOR

/// A small, deterministic PRNG (SplitMix64) so the fuzz inputs are reproducible.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// These tests guard against the SwiftCBOR crash that motivated this library:
/// decoding random/adversarial bytes used to trap with EXC_BAD_ACCESS (a stack
/// overflow from unbounded recursion). See
/// https://github.com/valpackett/SwiftCBOR/issues/92 and swift-webauthn#36.
///
/// A crash here would abort the whole test process, so "these tests pass" means
/// "no input crashed the decoder".
@Suite("Fuzz safety")
struct FuzzSafetyTests {
    @Test("decoding random bytes never crashes")
    func randomBytesDoNotCrash() {
        var rng = SplitMix64(seed: 0x5EED_C0FF_EE12_3456)
        for _ in 0..<5000 {
            let length = Int.random(in: 0...4096, using: &rng)
            var bytes: [UInt8] = []
            bytes.reserveCapacity(length)
            for _ in 0..<length { bytes.append(UInt8.random(in: 0...255, using: &rng)) }
            _ = try? CBOR.decode(bytes)
            _ = try? CBOR.decodeFirst(bytes)
        }
        #expect(Bool(true)) // reaching this line means nothing trapped
    }

    @Test("decoding large random buffers never crashes (mirrors the original report)")
    func largeRandomBuffersDoNotCrash() {
        var rng = SplitMix64(seed: 0xA5A5_1234_9876_FEDC)
        for _ in 0..<5 {
            let length = Int.random(in: 100_000...1_000_000, using: &rng)
            var bytes: [UInt8] = []
            bytes.reserveCapacity(length)
            for _ in 0..<length { bytes.append(UInt8.random(in: 0...255, using: &rng)) }
            _ = try? CBOR.decode(bytes)
        }
        #expect(Bool(true))
    }

    @Test("deep nesting is bounded rather than overflowing the stack")
    func deepNestingThrows() {
        // Each of these nests ~100k levels — without the depth guard the parser
        // would recurse until the stack overflows and the process traps.
        let nestedArrays = [UInt8](repeating: 0x81, count: 100_000) + [0x00] // array(1) × N
        let nestedTags = [UInt8](repeating: 0xc0, count: 100_000) + [0x00]   // tag × N
        let nestedIndefinite = [UInt8](repeating: 0x9f, count: 100_000) + [0x00] // array(_) × N
        var nestedMaps: [UInt8] = []
        for _ in 0..<100_000 { nestedMaps += [0xa1, 0x00] } // map(1) with key 0, value = next
        nestedMaps.append(0x00)

        let inputs: [[UInt8]] = [nestedArrays, nestedTags, nestedIndefinite, nestedMaps]
        for input in inputs {
            #expect(throws: CBORError.maxDepthExceeded(512)) {
                try CBOR.decode(input)
            }
        }
    }

    @Test("oversized declared lengths fail fast without over-allocating")
    func hugeDeclaredLengthsAreSafe() {
        let cases: [[UInt8]] = [
            [0x9b] + [UInt8](repeating: 0xff, count: 8), // array, length 2^64-1
            [0x9a, 0xff, 0xff, 0xff, 0xff],              // array, length ~4.3 billion
            [0xbb] + [UInt8](repeating: 0xff, count: 8), // map, 2^64-1 pairs
            [0x5b] + [UInt8](repeating: 0xff, count: 8), // byte string, 2^64-1 bytes
            [0x5a, 0xff, 0xff, 0xff, 0xff],              // byte string, ~4.3 GB
            [0x7b] + [UInt8](repeating: 0xff, count: 8), // text string, 2^64-1 bytes
        ]
        for input in cases {
            #expect(throws: (any Error).self) {
                try CBOR.decode(input)
            }
        }
    }

    @Test("truncated headers throw unexpectedEnd", arguments: [
        "18", "19", "1a", "1b",       // unsigned int, 1/2/4/8-byte argument missing
        "38", "39", "3a", "3b",       // negative int
        "58", "5820",                 // byte string length/body missing
        "78", "7820",                 // text string length/body missing
        "98", "9a000000",             // array count missing
        "b8", "bb00000000",           // map count missing
        "d8",                         // tag argument missing
        "f9", "fa", "fb", "f8",       // half/float/double/simple missing bytes
    ])
    func truncatedHeadersThrow(_ hex: String) {
        #expect(throws: (any Error).self) {
            try CBOR.decode(bytes(fromHex: hex))
        }
    }
}
