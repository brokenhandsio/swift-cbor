import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CBOR

/// Iteration count per fuzz loop. Modest by default so `swift test` stays quick;
/// override with the `CBOR_FUZZ_ITERATIONS` environment variable for deep runs.
private func iterations(_ fallback: Int) -> Int {
    if let raw = ProcessInfo.processInfo.environment["CBOR_FUZZ_ITERATIONS"],
       let value = Int(raw), value > 0 {
        return value
    }
    return fallback
}

private let decodeOptions = CBOROptions(maximumDepth: 32)

private struct Probe: Codable {
    var a: Int?
    var b: String?
    var c: [Double]?
    var d: [String: Int]?
    var e: Bool?
}

/// Generative fuzzing: reproducible, no vendored corpus. A crash in any loop aborts
/// the process, so "these tests pass" means "nothing crashed the decoder".
@Suite("Generative fuzzing")
struct GenerativeFuzzTests {
    /// Freshly generated CBOR must decode and survive a decode → encode → decode
    /// round trip (proving the decoder accepts valid, possibly non-canonical, input
    /// and that it agrees with the encoder).
    @Test("generated valid CBOR decodes and round-trips")
    func roundTrip() throws {
        var generator = CBORFuzzGenerator(seed: 0xF022_1234_5678_9ABC)
        for _ in 0..<iterations(10_000) {
            let bytes = generator.generate(maxDepth: Int(generator.nextUInt(5)))
            let value = try CBOR.decode(bytes, options: decodeOptions)
            let reDecoded = try CBOR.decode(value.encode(), options: decodeOptions)
            #expect(value == reDecoded)
        }
    }

    /// Corrupted "almost-valid" inputs — the highest-yield crash class.
    @Test("mutated inputs never crash the decoder")
    func mutated() {
        var generator = CBORFuzzGenerator(seed: 0xBEEF_5678_1234_DEAD)
        for _ in 0..<iterations(10_000) {
            var bytes = generator.generate(maxDepth: Int(generator.nextUInt(5)))
            generator.mutate(&bytes)
            _ = try? CBOR.decode(bytes, options: decodeOptions)
            _ = try? CBOR.decodeFirst(bytes, options: decodeOptions)
        }
        #expect(Bool(true))
    }

    /// Pure random byte streams.
    @Test("random inputs never crash the decoder")
    func random() {
        var rng = SplitMix64(seed: 0x1357_9BDF_2468_ACE0)
        for _ in 0..<iterations(10_000) {
            var bytes: [UInt8] = []
            for _ in 0..<Int(rng.next() % 96) { bytes.append(UInt8(truncatingIfNeeded: rng.next())) }
            _ = try? CBOR.decode(bytes)
            _ = try? CBOR.decodeFirst(bytes)
        }
        #expect(Bool(true))
    }

    /// A large combined pass, opt-in via the `CBOR_FUZZ_DEEP` environment variable
    /// (skipped by default so normal `swift test` runs stay quick). Suitable for a
    /// scheduled CI job or a local soak. Override the count with `CBOR_FUZZ_ITERATIONS`.
    @Test(
        "deep fuzzing pass",
        .enabled(if: ProcessInfo.processInfo.environment["CBOR_FUZZ_DEEP"] != nil)
    )
    func deepPass() throws {
        var generator = CBORFuzzGenerator(seed: 0xDEE9_0F22_1234_5678)
        var rng = SplitMix64(seed: 0x0DDF_ACE0_1357_9BDF)
        let decoder = CBORDecoder(options: decodeOptions)
        for _ in 0..<iterations(500_000) {
            // Valid input: decode and round-trip.
            let valid = generator.generate(maxDepth: Int(generator.nextUInt(6)))
            let value = try CBOR.decode(valid, options: decodeOptions)
            #expect(value == (try CBOR.decode(value.encode(), options: decodeOptions)))

            // Corrupted "almost-valid" input.
            var mutated = valid
            generator.mutate(&mutated)
            _ = try? CBOR.decode(mutated, options: decodeOptions)
            _ = try? CBOR.decodeFirst(mutated, options: decodeOptions)
            _ = try? decoder.decode(Probe.self, from: mutated)

            // Pure garbage.
            var random: [UInt8] = []
            for _ in 0..<Int(rng.next() % 128) { random.append(UInt8(truncatingIfNeeded: rng.next())) }
            _ = try? CBOR.decode(random)
            _ = try? decoder.decode(Probe.self, from: random)
        }
        #expect(Bool(true))
    }

    /// The Codable decoder must also survive fuzzed input across all container kinds.
    @Test("Codable decoding never crashes on fuzzed input")
    func codableProbe() {
        var generator = CBORFuzzGenerator(seed: 0x2468_ACE0_1357_9BDF)
        let decoder = CBORDecoder(options: decodeOptions)
        for index in 0..<iterations(6_000) {
            var bytes = generator.generate(maxDepth: Int(generator.nextUInt(4)))
            if index.isMultiple(of: 2) { generator.mutate(&bytes) }
            _ = try? decoder.decode(Int.self, from: bytes)
            _ = try? decoder.decode(String.self, from: bytes)
            _ = try? decoder.decode([Int].self, from: bytes)
            _ = try? decoder.decode([String: Int].self, from: bytes)
            _ = try? decoder.decode(Probe.self, from: bytes)
        }
        #expect(Bool(true))
    }
}
