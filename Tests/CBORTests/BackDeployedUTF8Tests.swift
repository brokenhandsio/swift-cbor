import Testing
@testable import CBOR

/// `CBORParser.validatedStringBackDeployed(_:)` is the UTF-8 check the decoder
/// falls back to on OSes that predate `String(validating:as:)`. Test hosts are new
/// enough that decoding never reaches it, so it is checked directly here against
/// the stdlib validator it stands in for.
@Suite("Back-deployed UTF-8 validation")
struct BackDeployedUTF8Tests {
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("agrees with String(validating:as:)", arguments: [
        "",                             // empty
        "61",                           // ASCII
        "c3bc", "e6b0b4", "f0908591",   // 2-, 3- and 4-byte sequences
        "efbfbd",                       // U+FFFD itself is well-formed
        "80",                           // lone continuation byte
        "ff", "f5808080",               // bytes that never occur in UTF-8
        "c080", "e08080", "f0808080",   // overlong encodings
        "eda080",                       // UTF-16 surrogate
        "f4908080",                     // above U+10FFFF
        "f09f98",                       // truncated, and repairs to the same length
        "efbf41",                       // truncated before ASCII
        "e6b0",                         // truncated at the end
        "61ff62",                       // ill-formed byte between valid ones
    ])
    func knownCases(_ hex: String) {
        let input = bytes(fromHex: hex)
        #expect(
            CBORParser.validatedStringBackDeployed(input)
                == String(validating: input, as: UTF8.self)
        )
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("agrees with String(validating:as:) on random input")
    func randomInput() {
        var rng = SplitMix64(seed: 0x0DD_B17E_5EED_F00D)
        // Bytes that sit on UTF-8's boundaries, so most inputs are valid, nearly
        // valid, or ill-formed in an interesting way rather than plain noise.
        let alphabet: [UInt8] = [
            0x00, 0x41, 0x7f, 0x80, 0x8f, 0x90, 0x9f, 0xa0, 0xbd, 0xbf,
            0xc0, 0xc1, 0xc2, 0xdf, 0xe0, 0xed, 0xef, 0xf0, 0xf4, 0xf5, 0xff,
        ]
        var mismatches = 0
        for _ in 0..<50_000 {
            let input = (0..<Int.random(in: 0...12, using: &rng)).map { _ in
                alphabet.randomElement(using: &rng)!
            }
            if CBORParser.validatedStringBackDeployed(input)
                != String(validating: input, as: UTF8.self) {
                mismatches += 1
                Issue.record("mismatch for \(hexString(input))")
                if mismatches > 10 { return }
            }
        }
    }
}
