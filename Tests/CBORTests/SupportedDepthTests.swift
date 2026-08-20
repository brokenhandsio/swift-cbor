import Testing
import CBOR

// `depth` nested indefinite-length arrays, closed with the matching breaks.
private func nestedIndefiniteArrays(_ depth: Int) -> [UInt8] {
    [UInt8](repeating: 0x9f, count: depth) + [0x00] + [UInt8](repeating: 0xff, count: depth)
}

@Suite("Supported depth ceiling")
struct SupportedDepthTests {
    @Test("Decoding at the ceiling succeeds")
    func atCeiling() throws {
        let bytes = nestedIndefiniteArrays(CBOROptions.maximumSupportedDepth - 1)
        let options = CBOROptions(maximumDepth: .max)
        _ = try CBOR.decode(bytes, options: options)
    }

    @Test("Raising maximumDepth past the ceiling does not raise the ceiling")
    func ceilingIsNotNegotiable() {
        // Before this cap the value below decoded successfully and then crashed
        // when it was released — a stack overflow the caller could not catch.
        // Now it is an ordinary error.
        let bytes = nestedIndefiniteArrays(CBOROptions.maximumSupportedDepth + 200)
        #expect(throws: CBORError.self) {
            try CBOR.decode(bytes, options: CBOROptions(maximumDepth: .max))
        }
        #expect(throws: CBORError.self) {
            try CBOR.decode(bytes, options: CBOROptions(maximumDepth: 100_000))
        }
    }

    @Test("A lower maximumDepth is still honoured")
    func lowerLimitsStillApply() {
        // The clamp is a ceiling, not an override.
        #expect(throws: CBORError.self) {
            try CBOR.decode(nestedIndefiniteArrays(20), options: CBOROptions(maximumDepth: 10))
        }
    }

    @Test("The default limit is well inside the ceiling")
    func defaultIsInsideCeiling() {
        #expect(CBOROptions.default.maximumDepth <= CBOROptions.maximumSupportedDepth)
    }

    @Test("A value decoded at the ceiling can be released without overflowing")
    func decodedValueTearsDownSafely() throws {
        // The actual failure this cap exists to prevent: teardown, not parsing.
        // Runs on a Task thread, whose stack is the smaller of the two cases
        // that matter (~1,800 levels measured, versus ~30,000 on the main thread).
        for _ in 0..<5 {
            let value = try CBOR.decode(
                nestedIndefiniteArrays(CBOROptions.maximumSupportedDepth - 1),
                options: CBOROptions(maximumDepth: .max))
            if case .array = value {} else { Issue.record("expected an array") }
        }
    }
}
